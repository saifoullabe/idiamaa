-- =====================================================================
-- IDIAMA AGRO — 13. La validation, les salaires et les sorties de zone
-- À lancer après 12. Relançable sans risque.
--
-- ⚠ Si l'éditeur SQL affiche un avertissement, répondez « Run without RLS ».
--
-- Trois corrections :
--   A. Les salaires ne sont plus lisibles que par l'administrateur.
--   B. Une saisie naît en attente et n'est validée que par l'échelon
--      juste au-dessus — jamais par celui qui l'a saisie.
--   C. Les sorties de zone d'une autre ferme ne sont plus modifiables.
--
-- LE TABLEAU DU BAS : les lignes A, B et C doivent afficher OK. Une
-- ligne peut afficher INFO quand l'essai n'est pas jouable (une base
-- sans gérant, par exemple) : ce n'est pas un problème.
-- =====================================================================

-- =====================================================================
-- A. LES SALAIRES
-- Le gérant lisait la fiche complète de ses collègues — salaire,
-- filiation, date de naissance — en interrogeant la table directement.
-- L'application, elle, passe déjà par la vue « collegues », qui ne
-- montre pas ces colonnes. On ferme donc la table : chacun lit sa
-- propre fiche, l'administrateur lit tout, et le gérant garde la vue.
-- =====================================================================
do $$
declare r record;
begin
  for r in select policyname from pg_policies
            where schemaname = 'public' and tablename = 'profils'
              and cmd in ('SELECT', 'ALL')
  loop
    execute format('drop policy %I on public.profils', r.policyname);
  end loop;
end $$;
create policy profils_lecture on public.profils for select to authenticated
  using (id = auth.uid() or public.mon_role() = 'admin');

-- =====================================================================
-- B. CHAQUE SAISIE EST VALIDÉE PAR L'ÉCHELON JUSTE AU-DESSUS
--
-- La règle était écrite dans l'application seulement. En base, un
-- gérant pouvait valider une saisie en attente de l'ADMINISTRATEUR, et
-- surtout valider la sienne. Il pouvait même créer une ligne déjà
-- « validée » : l'argent entrait dans les totaux sans que personne ne
-- l'ait vérifié. Le verrou couvre donc la création ET la modification.
-- =====================================================================
create or replace function public.valider_par_le_dessus()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare qui text := coalesce(public.mon_role(), 'aucun');
begin
  -- Le propriétaire qui répare une ligne depuis l'éditeur SQL n'a aucun
  -- jeton : ce n'est pas un utilisateur de l'application, et la base ne
  -- doit pas lui barrer la route — sinon une saisie coincée le reste.
  -- L'application, elle, a toujours un jeton.
  if coalesce(current_setting('request.jwt.claims', true), '') = ''
     and auth.uid() is null then
    return new;
  end if;

  -- ── À la création : une saisie naît au niveau de celui qui la crée ──
  if tg_op = 'INSERT' then
    if qui = 'admin' then return new; end if;
    if new.auteur_id is distinct from auth.uid() then
      raise exception 'Une saisie se cree en votre nom';
    end if;
    if qui = 'gerant'  and new.statut = 'attente_admin'  then return new; end if;
    if qui = 'fermier' and new.statut = 'attente_gerant' then return new; end if;
    raise exception 'Une saisie se cree en attente de validation, pas validee';
  end if;

  -- ── À la modification ──
  if new.statut is not distinct from old.statut then
    return new;
  end if;

  -- Un fermier ne valide ni ne rejette jamais. Il peut redéposer sa
  -- propre saisie tant qu'elle n'est pas validée.
  if qui = 'fermier' then
    if new.auteur_id = auth.uid()
       and new.statut = 'attente_gerant'
       and old.statut in ('rejete', 'attente_gerant', 'attente_admin') then
      return new;
    end if;
    raise exception 'Seule une saisie non validee peut etre modifiee, et seul votre responsable peut la valider ou la rejeter';
  end if;

  if new.statut in ('valide', 'rejete') then
    -- Personne ne valide sa propre saisie. Exception : un fermier promu
    -- gérant valide celles qu'il avait faites AVANT, comme fermier —
    -- sans quoi elles resteraient coincées hors des totaux pour toujours.
    if new.auteur_id = auth.uid() and qui <> 'admin'
       and coalesce(old.role_auteur, '') <> 'fermier' then
      raise exception 'Vous ne pouvez pas valider votre propre saisie';
    end if;
    -- Ce qui attend l'administrateur n'est validé que par lui.
    if old.statut = 'attente_admin' and qui <> 'admin' then
      raise exception 'Cette saisie attend l administrateur';
    end if;
    if qui not in ('admin', 'gerant') then
      raise exception 'Reserve au gerant et a l administrateur';
    end if;
  end if;

  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['recettes', 'depenses', 'productions', 'depots']
  loop
    execute format('drop trigger if exists trg_valider_%1$s on public.%1$I', t);
    execute format(
      'create trigger trg_valider_%1$s before insert or update on public.%1$I '
      'for each row execute function public.valider_par_le_dessus()', t);
  end loop;
end $$;

-- =====================================================================
-- C. LES SORTIES DE ZONE D'UNE AUTRE FERME
-- « Vu par l'administrateur » pouvait être coché par le gérant de
-- n'importe quelle ferme, sur la sortie de n'importe qui.
-- =====================================================================
do $$
declare r record;
begin
  for r in select policyname from pg_policies
            where schemaname = 'public' and tablename = 'sorties_zone'
              and cmd in ('UPDATE', 'ALL')
  loop
    execute format('drop policy %I on public.sorties_zone', r.policyname);
  end loop;
end $$;
create policy sortie_maj on public.sorties_zone for update to authenticated
  using (public.ma_ferme_est(ferme_id)
         and public.mon_role() in ('admin', 'gerant'))
  with check (public.ma_ferme_est(ferme_id));

-- =====================================================================
-- CONTRÔLE — on fait le geste, et on l'ANNULE
--
-- Une recette d'essai est créée, on tente de la valider en se faisant
-- passer pour son auteur, puis tout le bloc est annulé par une erreur
-- volontaire : il n'y a aucun effacement à faire, et aucun chemin ne
-- peut laisser de ligne dans vos comptes.
-- =====================================================================
create or replace function public.idiama_controle_13()
returns table (verification text, resultat text)
language plpgsql security definer
set search_path = public, extensions as $$
declare
  ger   uuid;
  ferme uuid;
  essai uuid;
  msg   text;
  n     integer;
begin
  verification := 'A. Les salaires ne sont lisibles que par l administrateur';
  select count(*) into n from pg_policies
   where schemaname = 'public' and tablename = 'profils' and cmd in ('SELECT', 'ALL')
     and (qual is null or qual like '%ma_ferme%' or qual like '%gerant%');
  resultat := case when n = 0 then 'OK'
              else 'ECHEC — ' || n::text || ' regle(s) laissent le gerant tout lire' end;
  return next;

  verification := 'A. Chacun lit toujours sa propre fiche';
  resultat := case when exists (
      select 1 from pg_policies where schemaname = 'public' and tablename = 'profils'
        and cmd = 'SELECT' and qual like '%auth.uid()%')
    then 'OK' else 'ECHEC — plus personne ne lirait sa fiche' end;
  return next;

  verification := 'B. Le verrou est pose sur les 4 tables, creation comprise';
  select count(*) into n from pg_trigger g
    join pg_class c on c.oid = g.tgrelid
    join pg_namespace s on s.oid = c.relnamespace
   where s.nspname = 'public' and not g.tgisinternal
     and g.tgname in ('trg_valider_recettes', 'trg_valider_depenses',
                      'trg_valider_productions', 'trg_valider_depots')
     and (g.tgtype & 4) = 4 and (g.tgtype & 16) = 16;
  resultat := case when n = 4 then 'OK'
              else 'ECHEC — ' || n::text || ' sur 4 couvrent creation et modification' end;
  return next;

  verification := 'B. Il reste un administrateur pour valider';
  resultat := case when exists (
      select 1 from public.profils where role = 'admin' and not suspendu)
    then 'OK' else 'ECHEC — aucun administrateur actif : plus personne ne peut valider' end;
  return next;

  -- ── Le geste ──
  -- Il faut un GERANT : l'administrateur, lui, a le droit de valider sa
  -- propre saisie, le test ne prouverait rien avec lui.
  select p.id, p.ferme_id into ger, ferme from public.profils p
   where p.role = 'gerant' and not p.suspendu and p.ferme_id is not null
   order by p.cree_le limit 1;

  if ger is null then
    verification := 'B. Valider sa propre saisie est refuse';
    resultat := 'INFO — pas testable tant qu aucun gerant n est rattache a une ferme';
    return next;
    verification := 'B. Creer une saisie deja validee est refuse';
    resultat := 'INFO — pas testable tant qu aucun gerant n est rattache a une ferme';
    return next;
  else
    -- Essai 1 : valider sa propre saisie.
    begin
      insert into public.recettes
        (ferme_id, auteur_id, role_auteur, produit, quantite,
         prix_unitaire, montant, description, date, statut)
      values (ferme, ger, 'gerant', 'Controle 13', 0, 0, 0,
              'Controle 13, annule aussitot', current_date, 'attente_gerant')
      returning id into essai;

      perform set_config('request.jwt.claims',
        json_build_object('sub', ger::text, 'role', 'authenticated')::text, true);
      perform set_config('request.jwt.claim.sub', ger::text, true);

      begin
        update public.recettes set statut = 'valide' where id = essai;
        resultat := 'ECHEC — la saisie a ete validee par son propre auteur';
      exception when others then
        msg := sqlerrm;
        resultat := case
          when msg like '%propre saisie%' or msg like '%attend l administrateur%'
            then 'OK' else 'ECHEC — ' || msg end;
      end;

      -- Tout ce bloc est annule : la ligne d essai n a jamais existe.
      raise exception 'IDIAMA_13_ANNULE';
    exception when others then
      if sqlerrm <> 'IDIAMA_13_ANNULE' then
        resultat := 'ECHEC — ' || sqlerrm;
      end if;
    end;
    verification := 'B. Valider sa propre saisie est refuse';
    return next;

    -- Essai 2 : creer une ligne deja validee.
    begin
      perform set_config('request.jwt.claims',
        json_build_object('sub', ger::text, 'role', 'authenticated')::text, true);
      perform set_config('request.jwt.claim.sub', ger::text, true);
      begin
        insert into public.recettes
          (ferme_id, auteur_id, role_auteur, produit, quantite,
           prix_unitaire, montant, description, date, statut)
        values (ferme, ger, 'gerant', 'Controle 13', 0, 0, 0,
                'Controle 13, annule aussitot', current_date, 'valide');
        resultat := 'ECHEC — une saisie deja validee a pu etre creee';
      exception when others then
        msg := sqlerrm;
        resultat := case when msg like '%attente de validation%'
                    then 'OK' else 'ECHEC — ' || msg end;
      end;
      raise exception 'IDIAMA_13_ANNULE';
    exception when others then
      if sqlerrm <> 'IDIAMA_13_ANNULE' then
        resultat := 'ECHEC — ' || sqlerrm;
      end if;
    end;
    verification := 'B. Creer une saisie deja validee est refuse';
    return next;
  end if;

  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);

  verification := 'B. Aucune ligne de controle ne traine dans vos comptes';
  resultat := case when not exists (
      select 1 from public.recettes where description = 'Controle 13, annule aussitot')
    then 'OK' else 'ECHEC — effacez les recettes nommees Controle 13' end;
  return next;

  verification := 'C. Les sorties d une autre ferme ne sont plus modifiables';
  select count(*) into n from pg_policies
   where schemaname = 'public' and tablename = 'sorties_zone' and cmd in ('UPDATE', 'ALL')
     and (qual is null or qual not like '%ma_ferme_est%');
  resultat := case when n = 0 then 'OK'
              else 'ECHEC — ' || n::text || ' regle(s) sans controle de ferme' end;
  return next;

  verification := 'INFO. Saisies en attente dans vos comptes';
  select count(*) into n from (
    select 1 from public.recettes    where statut like 'attente%'
    union all select 1 from public.depenses    where statut like 'attente%'
    union all select 1 from public.productions where statut like 'attente%'
    union all select 1 from public.depots      where statut like 'attente%') x;
  resultat := n::text || ' saisie(s) attendent une validation';
  return next;
end $$;

revoke all on function public.idiama_controle_13() from public, anon, authenticated;
revoke all on function public.valider_par_le_dessus() from public, anon;

notify pgrst, 'reload schema';

select * from public.idiama_controle_13();
