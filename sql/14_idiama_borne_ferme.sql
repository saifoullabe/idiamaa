-- =====================================================================
-- IDIAMA AGRO — 14. Le premier pointage pose la borne de la ferme
-- À lancer après 13. Relançable sans risque.
--
-- ⚠ Si l'éditeur SQL affiche un avertissement, répondez « Run without RLS ».
--
-- Décidé le 21/10/2026.
--
-- Avant : seul l'administrateur pouvait enregistrer la position d'une
-- ferme — et tant qu'elle n'était pas posée, le fermier pointait depuis
-- n'importe où, le contrôle ne s'appliquant qu'aux fermes repérées.
--
-- Maintenant : le TOUT PREMIER pointage d'un fermier pose la position
-- de sa ferme, à l'endroit où il se trouve. Tous les pointages suivants
-- sont comparés à ce point. Le fermier ne peut plus y toucher ensuite,
-- et l'administrateur voit qui l'a posée, quand et où, avec le droit de
-- la confirmer, de la corriger ou de l'effacer.
--
-- La triche possible se limite donc au premier jour — et elle est
-- visible, datée et nominative.
--
-- Les lignes A à D du tableau du bas doivent afficher OK.
-- =====================================================================

-- =====================================================================
-- A. QUI A POSÉ LA BORNE, ET QUAND
-- =====================================================================
alter table public.fermes
  add column if not exists position_posee_par   uuid references public.profils(id) on delete set null,
  add column if not exists position_posee_le    timestamptz,
  add column if not exists position_precision   integer,
  add column if not exists position_confirmee   boolean not null default false;

-- Les fermes dont la position était déjà posée par l'administrateur
-- sont considérées comme confirmées : lui seul pouvait les écrire.
update public.fermes
   set position_confirmee = true
 where latitude is not null and position_posee_par is null
   and position_confirmee = false;

-- =====================================================================
-- B. LE PREMIER POINTAGE POSE LA BORNE
-- Même signature qu'avant : l'application appelle déjà cette fonction.
-- =====================================================================
-- La signature change (la précision du GPS s'ajoute) : on retire
-- l'ancienne, sinon les deux coexisteraient et l'appel deviendrait
-- ambigu.
drop function if exists public.pointer_arrivee(double precision, double precision);

create or replace function public.pointer_arrivee(
  p_latitude  double precision,
  p_longitude double precision,
  p_precision double precision default null
)
returns table (message text, distance integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  moi    public.profils%rowtype;
  f      public.fermes%rowtype;
  dist   double precision;
  pose   boolean := false;
begin
  select * into moi from public.profils where id = auth.uid();
  if moi.id is null then raise exception 'Connexion requise'; end if;
  if moi.suspendu then raise exception 'Compte suspendu'; end if;

  if exists (select 1 from public.pointages
              where profil_id = moi.id and statut = 'en_cours') then
    raise exception 'Vous êtes déjà en ligne';
  end if;

  select * into f from public.fermes where id = moi.ferme_id;

  -- L'admin et le gérant pointent sans contrainte de lieu ; c'est le
  -- fermier qu'on attend physiquement sur l'exploitation.
  if moi.role = 'fermier' and f.id is not null then
    if p_latitude is null or p_longitude is null then
      raise exception 'Position introuvable. Activez la localisation du téléphone.';
    end if;

    if f.latitude is null or f.longitude is null then
      -- Ce point va servir de centre à TOUS les pointages suivants : on
      -- refuse de le poser avec un relevé grossier. Sous une tôle ou en
      -- ville, le GPS d'un téléphone se trompe de plusieurs centaines
      -- de mètres, et le cercle serait décalé pour toujours.
      if p_precision is not null and p_precision > 100 then
        raise exception 'Le GPS est trop imprecis pour poser le repere de la ferme (% m). Sortez a ciel ouvert, attendez quelques secondes et reessayez.',
          round(p_precision)::text;
      end if;
      -- Première fois : c'est ce pointage qui définit la ferme. On le
      -- marque pour que l'administrateur le voie et puisse corriger.
      update public.fermes
         set latitude           = p_latitude,
             longitude          = p_longitude,
             position_posee_par = moi.id,
             position_posee_le  = now(),
             position_precision = case when p_precision is null then null
                                  else round(p_precision)::int end,
             position_confirmee = false
       where id = f.id;
      pose := true;
      dist := 0;
    else
      dist := public.distance_metres(f.latitude, f.longitude,
                                     p_latitude, p_longitude);
      if dist > f.rayon_metres then
        raise exception 'Vous êtes à % m de la ferme %. Le pointage n''est possible que sur place (moins de % m).',
          round(dist)::text, f.nom, f.rayon_metres::text;
      end if;
    end if;
  end if;

  insert into public.pointages
    (profil_id, ferme_id, debut, statut, latitude, longitude, distance_metres)
  values
    (moi.id, moi.ferme_id, now(), 'en_cours',
     p_latitude, p_longitude,
     case when dist is null then null else round(dist)::int end);

  message := case when pose
    then 'Arrivée enregistrée. Cette position devient le repère de la ferme.'
    else 'Arrivée enregistrée' end;
  distance := case when dist is null then null else round(dist)::int end;
  return next;
end $$;

revoke all on function public.pointer_arrivee(double precision, double precision, double precision) from public, anon;
grant execute on function public.pointer_arrivee(double precision, double precision, double precision) to authenticated;

-- =====================================================================
-- C. L'ADMINISTRATEUR CONFIRME, CORRIGE OU EFFACE
-- Confirmer ne déplace rien : cela dit seulement « j'ai regardé, c'est
-- bien là ». Corriger et effacer passent par la fiche de la ferme,
-- comme avant.
-- =====================================================================
create or replace function public.admin_confirmer_position(p_ferme uuid)
returns void language plpgsql security definer
set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  if coalesce(public.mon_role(), 'aucun') <> 'admin' then
    raise exception 'Reserve a l administrateur';
  end if;
  if not exists (select 1 from public.fermes where id = p_ferme) then
    raise exception 'Ferme introuvable';
  end if;
  if not exists (select 1 from public.fermes
                  where id = p_ferme and latitude is not null) then
    raise exception 'Cette ferme n a pas encore de position';
  end if;
  update public.fermes set position_confirmee = true where id = p_ferme;
end $$;

revoke all on function public.admin_confirmer_position(uuid) from public, anon;
grant execute on function public.admin_confirmer_position(uuid) to authenticated;

-- Quand l'administrateur repose la position à la main depuis la fiche,
-- elle est confirmée d'office et cesse d'être attribuée à un fermier.
create or replace function public.ferme_position_admin()
returns trigger language plpgsql security definer
set search_path = public as $$
begin
  if new.latitude is distinct from old.latitude
     or new.longitude is distinct from old.longitude then
    -- Seul l'administrateur peut écrire la table fermes (regle
    -- fermes_maj) ; la fonction de pointage, elle, est security definer
    -- et pose « posee_par », ce qui la distingue.
    if new.position_posee_par is not distinct from old.position_posee_par then
      new.position_posee_par := null;
      if new.latitude is null or new.longitude is null then
        -- Position retirée : il n'y a rien à confirmer, et le prochain
        -- pointage reposera la borne.
        new.position_posee_le  := null;
        new.position_confirmee := false;
      else
        new.position_posee_le  := now();
        new.position_confirmee := true;
      end if;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_ferme_position_admin on public.fermes;
create trigger trg_ferme_position_admin
  before update on public.fermes
  for each row execute function public.ferme_position_admin();

revoke all on function public.ferme_position_admin() from public, anon;

-- =====================================================================
-- CONTRÔLE
-- =====================================================================
create or replace function public.idiama_controle_14()
returns table (verification text, resultat text)
language plpgsql security definer
set search_path = public, extensions as $$
declare n integer;
begin
  verification := 'A. La ferme retient qui a pose sa position';
  select count(*) into n from information_schema.columns
   where table_schema = 'public' and table_name = 'fermes'
     and column_name in ('position_posee_par', 'position_posee_le',
                         'position_precision', 'position_confirmee');
  resultat := case when n = 4 then 'OK' else 'ECHEC — ' || n::text || ' sur 4' end;
  return next;

  verification := 'A. Une seule version de pointer_arrivee';
  select count(*) into n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
   where s.nspname = 'public' and p.proname = 'pointer_arrivee';
  resultat := case
    when n = 1 and to_regprocedure(
      'public.pointer_arrivee(double precision,double precision,double precision)') is not null
      then 'OK'
    when n <> 1 then 'ECHEC — ' || n::text || ' versions, l appel serait ambigu'
    else 'ECHEC — la signature attendue par l application n existe pas' end;
  return next;

  verification := 'A. Un repere ne se pose pas avec un GPS grossier';
  resultat := case when exists (
      select 1 from pg_proc p join pg_namespace s on s.oid = p.pronamespace
       where s.nspname = 'public' and p.proname = 'pointer_arrivee'
         and pg_get_functiondef(p.oid) like '%trop imprecis%')
    then 'OK' else 'ECHEC' end;
  return next;

  verification := 'B. Le pointage pose la borne quand elle manque';
  resultat := case when exists (
      select 1 from pg_proc p join pg_namespace s on s.oid = p.pronamespace
       where s.nspname = 'public' and p.proname = 'pointer_arrivee'
         and pg_get_functiondef(p.oid) like '%position_posee_par = moi.id%')
    then 'OK' else 'ECHEC — l ancienne version est encore en place' end;
  return next;

  verification := 'B. Un fermier sans position GPS est toujours refuse';
  resultat := case when exists (
      select 1 from pg_proc p join pg_namespace s on s.oid = p.pronamespace
       where s.nspname = 'public' and p.proname = 'pointer_arrivee'
         and pg_get_functiondef(p.oid) like '%Activez la localisation%')
    then 'OK' else 'ECHEC' end;
  return next;

  verification := 'C. Confirmer une position est reserve a l administrateur';
  begin
    perform public.admin_confirmer_position('00000000-0000-0000-0000-000000000000');
    resultat := 'ECHEC — la fonction a laisse passer';
  exception when others then
    resultat := case when sqlerrm in ('Connexion requise', 'Reserve a l administrateur')
                then 'OK' else 'ECHEC — ' || sqlerrm end;
  end;
  return next;

  verification := 'C. La fiche de la ferme reconfirme la position';
  resultat := case when exists (
      select 1 from pg_trigger g join pg_class c on c.oid = g.tgrelid
        join pg_namespace s on s.oid = c.relnamespace
       where s.nspname = 'public' and c.relname = 'fermes'
         and g.tgname = 'trg_ferme_position_admin' and not g.tgisinternal)
    then 'OK' else 'ECHEC' end;
  return next;

  verification := 'D. Le fermier ne peut toujours pas ecrire dans fermes';
  resultat := case when not exists (
      select 1 from pg_policies where schemaname = 'public' and tablename = 'fermes'
        and cmd in ('UPDATE', 'ALL') and (qual is null or qual not like '%admin%'))
    then 'OK' else 'ECHEC — une regle laisse ecrire un non-admin' end;
  return next;

  select count(*) into n from public.fermes where latitude is null;
  verification := 'INFO. Fermes sans position';
  resultat := case when n = 0 then 'aucune — le controle de lieu couvre tout'
              else n::text || ' — leur premier pointage posera la borne' end;
  return next;

  select count(*) into n from public.fermes
   where latitude is not null and not position_confirmee;
  verification := 'INFO. Positions a confirmer par vous';
  resultat := case when n = 0 then 'aucune'
              else n::text || ' — a verifier dans l onglet Fermes' end;
  return next;
end $$;

revoke all on function public.idiama_controle_14() from public, anon, authenticated;

notify pgrst, 'reload schema';

select * from public.idiama_controle_14();
