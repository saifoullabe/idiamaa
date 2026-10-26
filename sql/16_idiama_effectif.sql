-- =====================================================================
-- IDIAMA AGRO — 16. Le fermier renseigne l'effectif du bâtiment
-- À lancer après 15, puis le fichier 17. Relançable sans risque.
--
-- ⚠ Si l'éditeur SQL affiche un avertissement, répondez « Run without RLS ».
--
-- Décidé le 26/10/2026.
--
-- Avant : seuls l'administrateur et le gérant pouvaient écrire le
-- nombre de poulets d'un bâtiment. Le fermier, qui est devant les
-- cages, ne pouvait pas — et tant que le nombre valait zéro, le
-- pourcentage de ponte ne pouvait pas se calculer.
--
-- Maintenant :
--   — le fermier le pose UNE FOIS, et seulement si le bâtiment n'en a
--     pas encore. Ensuite il n'y touche plus : c'est la déclaration des
--     morts qui fait baisser l'effectif vivant ;
--   — le gérant ou l'administrateur peut le CORRIGER, parce qu'une
--     faute de frappe — 20 000 au lieu de 2 000 — fausse tous les
--     pourcentages du bâtiment et que le fermier, lui, ne peut plus y
--     revenir ;
--   — corriger ne déplace PAS la date du comptage : les morts déjà
--     déclarées restent déduites. Sinon la mortalité cumulée retombait
--     à zéro et les pourcentages des jours passés changeaient
--     rétroactivement, le jour d'une simple correction de saisie.
--
-- Vous voyez qui a posé le nombre, quand, et s'il a été vérifié.
--
-- Les lignes A à D du tableau du bas doivent afficher OK.
-- =====================================================================

-- =====================================================================
-- A. QUI A POSÉ L'EFFECTIF, ET QUAND
-- =====================================================================
alter table public.batiments
  add column if not exists effectif_pose_par  uuid references public.profils(id) on delete set null,
  add column if not exists effectif_pose_le   timestamptz,
  add column if not exists effectif_confirme  boolean not null default false;

-- Les bâtiments déjà renseignés l'ont été par un responsable : il n'y
-- a rien à vérifier.
update public.batiments
   set effectif_confirme = true
 where nb_poules > 0 and effectif_pose_par is null and effectif_confirme = false;

-- =====================================================================
-- B. LE FERMIER POSE L'EFFECTIF, UNE SEULE FOIS
-- =====================================================================
create or replace function public.poser_effectif(
  p_batiment uuid,
  p_nombre   integer)
returns integer language plpgsql security definer
set search_path = public as $$
declare
  moi public.profils%rowtype;
  b   public.batiments%rowtype;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  select * into moi from public.profils where id = auth.uid();
  if moi.id is null then raise exception 'Connexion requise'; end if;
  if moi.suspendu then raise exception 'Votre compte est suspendu'; end if;
  -- Comme toutes les autres écritures de la base : une ferme suspendue
  -- n'écrit plus. Sans cela, elle pouvait encore poser des effectifs.
  if not public.est_actif() then
    raise exception 'Votre ferme est suspendue : aucune saisie n''est possible.';
  end if;

  select * into b from public.batiments where id = p_batiment;
  if b.id is null then raise exception 'Bâtiment introuvable'; end if;
  if moi.role <> 'admin' and b.ferme_id is distinct from moi.ferme_id then
    raise exception 'Ce bâtiment n''est pas celui de votre ferme';
  end if;

  if p_nombre is null or p_nombre <= 0 then
    raise exception 'Indiquez combien de poulets sont dans ce bâtiment';
  end if;
  if p_nombre > 1000000 then
    raise exception 'Nombre invraisemblable : vérifiez votre saisie';
  end if;

  -- Une seule fois. Ensuite, c'est la déclaration des morts qui fait
  -- baisser l'effectif vivant — pas une réécriture du nombre de départ,
  -- qui effacerait toute la mortalité déjà enregistrée.
  if b.nb_poules > 0 then
    raise exception 'Ce bâtiment a déjà % poulets. Déclarez les morts au lieu de changer ce nombre. Si c''est une faute de frappe, votre gérant peut la corriger.',
      b.nb_poules::text;
  end if;

  -- Le déclencheur ne doit pas réécrire ce que l'on pose ici.
  perform set_config('idiama.effectif_rpc', '1', true);
  update public.batiments
     set nb_poules         = p_nombre,
         effectif_pose_par = moi.id,
         effectif_pose_le  = now(),
         effectif_confirme = (moi.role in ('admin', 'gerant'))
   where id = p_batiment;
  perform set_config('idiama.effectif_rpc', '', true);

  return p_nombre;
end $$;

revoke all on function public.poser_effectif(uuid, integer) from public, anon;
grant execute on function public.poser_effectif(uuid, integer) to authenticated;

-- =====================================================================
-- C. LE GÉRANT CORRIGE UNE FAUTE DE FRAPPE
--
-- Sans ce chemin, un fermier qui tapait 20 000 au lieu de 2 000 faussait
-- tous les pourcentages de son bâtiment pour toujours : lui ne pouvait
-- plus y revenir, et son gérant n'a pas accès à la fiche du bâtiment.
--
-- La date du comptage n'est PAS déplacée : les morts déjà déclarées
-- restent déduites, et l'histoire des jours passés ne change pas.
-- =====================================================================
create or replace function public.corriger_effectif(
  p_batiment uuid,
  p_nombre   integer)
returns integer language plpgsql security definer
set search_path = public as $$
declare
  moi public.profils%rowtype;
  b   public.batiments%rowtype;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  select * into moi from public.profils where id = auth.uid();
  if moi.id is null then raise exception 'Connexion requise'; end if;
  if moi.suspendu then raise exception 'Votre compte est suspendu'; end if;
  if moi.role not in ('admin', 'gerant') then
    raise exception 'Seul votre gérant peut corriger ce nombre. Montrez-lui le bâtiment.';
  end if;
  if not public.est_actif() then
    raise exception 'Votre ferme est suspendue : aucune saisie n''est possible.';
  end if;

  select * into b from public.batiments where id = p_batiment;
  if b.id is null then raise exception 'Bâtiment introuvable'; end if;
  if moi.role <> 'admin' and b.ferme_id is distinct from moi.ferme_id then
    raise exception 'Ce bâtiment n''est pas celui de votre ferme';
  end if;

  if p_nombre is null or p_nombre <= 0 then
    raise exception 'Indiquez le bon nombre de poulets';
  end if;
  if p_nombre > 1000000 then
    raise exception 'Nombre invraisemblable : vérifiez votre saisie';
  end if;
  if b.nb_poules = 0 then
    raise exception 'Ce bâtiment n''a pas encore d''effectif : c''est au fermier de le compter.';
  end if;

  perform set_config('idiama.effectif_rpc', '1', true);
  update public.batiments
     set nb_poules         = p_nombre,
         effectif_pose_par = moi.id,
         effectif_confirme = true,
         -- effectif_pose_le reste tel quel : voir l'en-tête. Sauf s'il
         -- manque — un bâtiment créé sans date n'aurait jamais eu de
         -- pourcentage de ponte, et c'est ici qu'on le répare.
         effectif_pose_le  = coalesce(b.effectif_pose_le,
                                      b.date_mise_en_place::timestamptz,
                                      b.cree_le)
   where id = p_batiment;
  perform set_config('idiama.effectif_rpc', '', true);

  return p_nombre;
end $$;

revoke all on function public.corriger_effectif(uuid, integer) from public, anon;
grant execute on function public.corriger_effectif(uuid, integer) to authenticated;

-- =====================================================================
-- D. L'ADMINISTRATEUR CONFIRME
-- Confirmer ne change aucun chiffre : cela dit « j'ai regardé ».
-- =====================================================================
create or replace function public.admin_confirmer_effectif(p_batiment uuid)
returns void language plpgsql security definer
set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  if coalesce(public.mon_role(), 'aucun') <> 'admin' then
    raise exception 'Réservé à l''administrateur';
  end if;
  if not exists (select 1 from public.batiments
                  where id = p_batiment and nb_poules > 0) then
    raise exception 'Ce bâtiment n''a pas encore d''effectif';
  end if;
  update public.batiments set effectif_confirme = true where id = p_batiment;
end $$;

revoke all on function public.admin_confirmer_effectif(uuid) from public, anon;
grant execute on function public.admin_confirmer_effectif(uuid) to authenticated;

-- Quand un responsable écrit l'effectif à la main depuis la fiche, il
-- est confirmé d'office et le comptage reçoit sa date.
--
-- À LA CRÉATION AUSSI, et c'est ce qui manquait : un bâtiment créé
-- depuis la fiche avec ses 600 poulets naissait sans date de comptage,
-- et un bâtiment sans date sort du pourcentage de ponte — ses œufs
-- comptaient dans le total mais jamais dans le taux. La ferme affichait
-- un beau pourcentage en ayant perdu un poulailler, et plus rien dans
-- l'application ne le réparait.
--
-- La date du comptage ne se déplace QUE lorsqu'il n'y en avait pas, ou
-- lorsque le bâtiment était vide, ou lorsqu'un nouveau lot arrive (le
-- jour d'arrivage change) — c'est-à-dire une vraie mise en place. Une
-- correction de nombre, elle, n'y touche pas : sinon toute la mortalité
-- déjà déclarée sortait du calcul, la mortalité cumulée retombait à
-- zéro et les pourcentages des jours passés changeaient rétroactivement.
create or replace function public.batiment_effectif_responsable()
returns trigger language plpgsql security definer
set search_path = public as $$
begin
  -- Écriture venue de poser_effectif ou corriger_effectif : elles ont
  -- déjà posé l'auteur et la date, on ne touche à rien. Avant, le
  -- déclencheur le devinait en comparant effectif_pose_par, et une
  -- deuxième correction par la même personne effaçait son nom.
  if coalesce(current_setting('idiama.effectif_rpc', true), '') = '1' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.nb_poules > 0 and new.effectif_pose_le is null then
      new.effectif_pose_le  := coalesce(new.date_mise_en_place::timestamptz,
                                        now());
      new.effectif_confirme := true;
    end if;
    return new;
  end if;

  if new.nb_poules is distinct from old.nb_poules
     or new.date_mise_en_place is distinct from old.date_mise_en_place then
    if new.nb_poules > 0 then
      if old.effectif_pose_le is null
         or coalesce(old.nb_poules, 0) = 0
         or new.date_mise_en_place is distinct from old.date_mise_en_place then
        -- Vraie mise en place : nouveau lot, ou premier comptage.
        new.effectif_pose_par := null;
        new.effectif_pose_le  := coalesce(new.date_mise_en_place::timestamptz,
                                          now());
        new.effectif_confirme := true;
      elsif new.nb_poules is distinct from old.nb_poules then
        -- Simple correction : la date ne bouge pas.
        new.effectif_pose_par := null;
        new.effectif_pose_le  := old.effectif_pose_le;
        new.effectif_confirme := true;
      end if;
    else
      -- Bâtiment vidé : on repart de zéro, le prochain comptage posera
      -- sa propre date.
      new.effectif_pose_par := null;
      new.effectif_pose_le  := null;
      new.effectif_confirme := false;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_batiment_effectif on public.batiments;
create trigger trg_batiment_effectif
  before insert or update on public.batiments
  for each row execute function public.batiment_effectif_responsable();

revoke all on function public.batiment_effectif_responsable() from public, anon;

-- =====================================================================
-- CONTRÔLE
-- Chaque vérification est dans son propre bloc : une erreur tardive
-- jetterait toutes les lignes déjà rendues, et le propriétaire ne
-- verrait rien du tout au lieu d'un tableau partiel.
-- =====================================================================
create or replace function public.idiama_controle_16()
returns table (verification text, resultat text)
language plpgsql security definer
set search_path = public, extensions as $$
declare
  n    integer;
  qui  uuid;
  ferm uuid;
  bat  uuid;
  mien uuid;
  msg  text;
begin
  -- On choisit un vrai fermier d'une ferme EN SERVICE : si la ferme du
  -- plus ancien fermier était suspendue, l'essai butait sur la garde
  -- « ferme suspendue » et ne prouvait rien de ce qu'il annonce.
  select p.id, p.ferme_id into qui, ferm
    from public.profils p
    join public.fermes f on f.id = p.ferme_id
   where p.role = 'fermier' and not p.suspendu and f.statut <> 'Suspendue'
   order by p.cree_le limit 1;
  select b.id into bat from public.batiments b
   where b.ferme_id is distinct from ferm limit 1;
  select b.id into mien from public.batiments b
   where b.ferme_id = ferm limit 1;

  verification := 'A. Le batiment retient qui a pose son effectif';
  begin
    select count(*) into n from information_schema.columns
     where table_schema = 'public' and table_name = 'batiments'
       and column_name in ('effectif_pose_par', 'effectif_pose_le',
                           'effectif_confirme');
    resultat := case when n = 3 then 'OK' else 'ECHEC — ' || n::text || ' sur 3' end;
  exception when others then resultat := 'ECHEC — ' || sqlerrm; end;
  return next;

  verification := 'A. Un batiment cree avec son effectif recoit sa date';
  begin
    -- Sans la branche d'insertion du declencheur, un batiment cree
    -- depuis la fiche naissait sans date de comptage, et un batiment
    -- sans date sort du pourcentage de ponte pour toujours.
    resultat := case when exists (
        select 1 from pg_trigger g join pg_class c on c.oid = g.tgrelid
          join pg_namespace s on s.oid = c.relnamespace
         where s.nspname = 'public' and c.relname = 'batiments'
           and g.tgname = 'trg_batiment_effectif' and not g.tgisinternal
           and (g.tgtype & 4) <> 0)     -- 4 = INSERT
      then 'OK' else 'ECHEC — le declencheur ne couvre pas la creation' end;
  exception when others then resultat := 'ECHEC — ' || sqlerrm; end;
  return next;

  verification := 'A. Aucun batiment a poules n est sans date de comptage';
  begin
    select count(*) into n from public.batiments
     where nb_poules > 0 and effectif_pose_le is null;
    resultat := case when n = 0 then 'OK'
                else 'ECHEC — ' || n::text || ' batiment(s) hors du pourcentage ; '
                     || 'relancez le fichier 17' end;
  exception when others then resultat := 'ECHEC — ' || sqlerrm; end;
  return next;

  verification := 'B. Poser un effectif est refuse a un inconnu';
  begin
    perform public.poser_effectif('00000000-0000-0000-0000-000000000000', 10);
    resultat := 'ECHEC — la fonction a laisse passer';
  exception when others then
    resultat := case when sqlerrm = 'Connexion requise'
                then 'OK' else 'ECHEC — ' || sqlerrm end;
  end;
  return next;

  -- On se fait passer pour un VRAI fermier : sans cela l'essai butait
  -- sur la garde de connexion et ne prouvait rien du reste. Tout le
  -- bloc est annule, donc si la garde avait disparu l'essai n'aurait
  -- rien ecrit dans une vraie ferme.
  verification := 'B. Un fermier ne pose pas l effectif d une autre ferme';
  begin
    if qui is null then
      resultat := 'INFO — pas testable tant qu aucun fermier n est rattache a une ferme en service';
    elsif bat is null then
      resultat := 'INFO — pas testable tant qu une seule ferme a des batiments';
    else
      perform set_config('request.jwt.claims',
        json_build_object('sub', qui::text, 'role', 'authenticated')::text, true);
      perform set_config('request.jwt.claim.sub', qui::text, true);
      begin
        begin
          perform public.poser_effectif(bat, 10);
          resultat := 'ECHEC — un fermier a pose l effectif d une autre ferme';
        exception when others then
          msg := sqlerrm;
          resultat := case when msg like '%pas celui de votre ferme%'
                      then 'OK' else 'ECHEC — ' || msg end;
        end;
        raise exception 'IDIAMA_16_ANNULE';
      exception when others then
        if sqlerrm <> 'IDIAMA_16_ANNULE' then
          resultat := 'ECHEC — ' || sqlerrm;
        end if;
      end;
      perform set_config('request.jwt.claims', '', true);
      perform set_config('request.jwt.claim.sub', '', true);
    end if;
  exception when others then
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    resultat := 'ECHEC — ' || sqlerrm;
  end;
  return next;

  verification := 'B. On ne peut pas reecrire un effectif deja pose';
  begin
    resultat := case when exists (
        select 1 from pg_proc p join pg_namespace s on s.oid = p.pronamespace
         where s.nspname = 'public' and p.proname = 'poser_effectif'
           and pg_get_functiondef(p.oid) like '%a déjà%')
      then 'OK' else 'ECHEC' end;
  exception when others then resultat := 'ECHEC — ' || sqlerrm; end;
  return next;

  verification := 'B. Une ferme suspendue ne pose plus d effectif';
  begin
    resultat := case when exists (
        select 1 from pg_proc p join pg_namespace s on s.oid = p.pronamespace
         where s.nspname = 'public' and p.proname = 'poser_effectif'
           and pg_get_functiondef(p.oid) like '%est_actif%')
      then 'OK' else 'ECHEC — la garde de ferme suspendue manque' end;
  exception when others then resultat := 'ECHEC — ' || sqlerrm; end;
  return next;

  -- Un fermier de SA propre ferme : c'est le seul essai qui atteigne la
  -- garde de role. Avec un identifiant inexistant, l'essai s'arretait
  -- sur « Connexion requise » et affichait OK quoi qu'il arrive.
  verification := 'C. Corriger est refuse au fermier';
  begin
    if qui is null or mien is null then
      resultat := 'INFO — pas testable tant qu aucun fermier n a de batiment';
    else
      perform set_config('request.jwt.claims',
        json_build_object('sub', qui::text, 'role', 'authenticated')::text, true);
      perform set_config('request.jwt.claim.sub', qui::text, true);
      begin
        begin
          perform public.corriger_effectif(mien, 1);
          resultat := 'ECHEC — un fermier a corrige l effectif';
        exception when others then
          msg := sqlerrm;
          resultat := case when msg like '%gérant%'
                      then 'OK' else 'ECHEC — ' || msg end;
        end;
        raise exception 'IDIAMA_16_ANNULE';
      exception when others then
        if sqlerrm <> 'IDIAMA_16_ANNULE' then
          resultat := 'ECHEC — ' || sqlerrm;
        end if;
      end;
      perform set_config('request.jwt.claims', '', true);
      perform set_config('request.jwt.claim.sub', '', true);
    end if;
  exception when others then
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    resultat := 'ECHEC — ' || sqlerrm;
  end;
  return next;

  verification := 'C. Corriger ne deplace pas la date du comptage';
  begin
    resultat := case when exists (
        select 1 from pg_proc p join pg_namespace s on s.oid = p.pronamespace
         where s.nspname = 'public' and p.proname = 'corriger_effectif'
           and pg_get_functiondef(p.oid) like '%reste tel quel%')
      then 'OK' else 'ECHEC — la correction reecrirait l historique' end;
  exception when others then resultat := 'ECHEC — ' || sqlerrm; end;
  return next;

  verification := 'C. La fiche non plus ne deplace pas la date';
  begin
    resultat := case when exists (
        select 1 from pg_proc p join pg_namespace s on s.oid = p.pronamespace
         where s.nspname = 'public' and p.proname = 'batiment_effectif_responsable'
           and pg_get_functiondef(p.oid) like '%Simple correction%')
      then 'OK' else 'ECHEC — relancez ce fichier' end;
  exception when others then resultat := 'ECHEC — ' || sqlerrm; end;
  return next;

  verification := 'C. Un nouveau lot ne herite pas des morts du precedent';
  begin
    resultat := case when exists (
        select 1 from pg_proc p join pg_namespace s on s.oid = p.pronamespace
         where s.nspname = 'public' and p.proname = 'batiment_effectif_responsable'
           and pg_get_functiondef(p.oid) like '%date_mise_en_place is distinct from old.date_mise_en_place%')
      then 'OK' else 'ECHEC — relancez ce fichier' end;
  exception when others then resultat := 'ECHEC — ' || sqlerrm; end;
  return next;

  verification := 'D. Confirmer est refuse au fermier';
  begin
    if qui is null or mien is null then
      resultat := 'INFO — pas testable tant qu aucun fermier n a de batiment';
    else
      perform set_config('request.jwt.claims',
        json_build_object('sub', qui::text, 'role', 'authenticated')::text, true);
      perform set_config('request.jwt.claim.sub', qui::text, true);
      begin
        begin
          perform public.admin_confirmer_effectif(mien);
          resultat := 'ECHEC — un fermier a confirme l effectif';
        exception when others then
          msg := sqlerrm;
          resultat := case when msg like '%administrateur%'
                      then 'OK' else 'ECHEC — ' || msg end;
        end;
        raise exception 'IDIAMA_16_ANNULE';
      exception when others then
        if sqlerrm <> 'IDIAMA_16_ANNULE' then
          resultat := 'ECHEC — ' || sqlerrm;
        end if;
      end;
      perform set_config('request.jwt.claims', '', true);
      perform set_config('request.jwt.claim.sub', '', true);
    end if;
  exception when others then
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    resultat := 'ECHEC — ' || sqlerrm;
  end;
  return next;

  verification := 'D. Un visiteur sans compte ne peut rien appeler';
  begin
    resultat := case when not (
        has_function_privilege('anon', 'public.poser_effectif(uuid,integer)', 'execute')
     or has_function_privilege('anon', 'public.corriger_effectif(uuid,integer)', 'execute')
     or has_function_privilege('anon', 'public.admin_confirmer_effectif(uuid)', 'execute'))
      then 'OK' else 'ECHEC — le role anon peut ecrire des effectifs' end;
  exception when others then resultat := 'ECHEC — ' || sqlerrm; end;
  return next;

  verification := 'INFO. Batiments sans effectif';
  begin
    select count(*) into n from public.batiments where nb_poules = 0;
    resultat := case when n = 0 then 'aucun'
                else n::text || ' — leur fermier pourra le renseigner' end;
  exception when others then resultat := 'ECHEC — ' || sqlerrm; end;
  return next;

  verification := 'INFO. Effectifs a confirmer par vous';
  begin
    select count(*) into n from public.batiments
     where nb_poules > 0 and not effectif_confirme and effectif_pose_par is not null;
    resultat := case when n = 0 then 'aucun'
                else n::text || ' — a verifier dans l onglet Sante' end;
  exception when others then resultat := 'ECHEC — ' || sqlerrm; end;
  return next;
end $$;

revoke all on function public.idiama_controle_16() from public, anon, authenticated;

notify pgrst, 'reload schema';

select * from public.idiama_controle_16();
