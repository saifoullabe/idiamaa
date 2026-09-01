-- =====================================================================
-- IDIAMA AGRO — Contrôle continu de la présence
-- À lancer après 07. Relançable sans risque.
--
-- Le téléphone envoie sa position régulièrement, même écran éteint et
-- application en arrière-plan. Deux verrous :
--
--   1. Le téléphone parle et la position est hors zone
--      → la base met le fermier hors ligne immédiatement.
--   2. Le téléphone se tait (application tuée, GPS coupé, batterie vide)
--      → au bout de 30 minutes sans nouvelles, la base ferme le
--        pointage toute seule. Le silence n'est plus une échappatoire.
-- =====================================================================

alter table public.pointages
  add column if not exists derniere_verif    timestamptz,
  add column if not exists derniere_distance integer,
  add column if not exists motif_sortie      text;

-- ── 1. Le téléphone dit où il est ────────────────────────────────────
create or replace function public.confirmer_presence(
  p_latitude  double precision,
  p_longitude double precision
)
returns table (en_ligne boolean, distance integer, motif text)
language plpgsql
security definer
set search_path = public
as $$
declare
  moi  public.profils%rowtype;
  f    public.fermes%rowtype;
  p    public.pointages%rowtype;
  dist double precision;
begin
  select * into moi from public.profils where id = auth.uid();
  if moi.id is null then raise exception 'Connexion requise'; end if;

  select * into p from public.pointages
   where profil_id = moi.id and statut = 'en_cours'
   order by debut desc limit 1;

  if p.id is null then
    en_ligne := false; distance := null; motif := 'Aucun pointage en cours';
    return next; return;
  end if;

  select * into f from public.fermes where id = p.ferme_id;

  -- Sans position enregistrée pour la ferme, il n'y a rien à contrôler.
  if f.id is null or f.latitude is null or f.longitude is null
     or moi.role <> 'fermier' then
    update public.pointages set derniere_verif = now() where id = p.id;
    en_ligne := true; distance := null; motif := 'Pas de controle sur cette ferme';
    return next; return;
  end if;

  if p_latitude is null or p_longitude is null then
    update public.pointages set derniere_verif = now() where id = p.id;
    en_ligne := true; distance := null; motif := 'Position non transmise';
    return next; return;
  end if;

  dist := public.distance_metres(f.latitude, f.longitude,
                                 p_latitude, p_longitude);

  update public.pointages
     set derniere_verif = now(),
         derniere_distance = round(dist)::int
   where id = p.id;

  if dist > f.rayon_metres then
    update public.pointages
       set fin = now(),
           duree = greatest(0, extract(epoch from (now() - debut))::int),
           statut = 'termine',
           lat_sortie = p_latitude,
           lon_sortie = p_longitude,
           sortie_auto = true,
           motif_sortie = 'Sorti de la zone de la ferme ('
                          || round(dist)::text || ' m)'
     where id = p.id;
    en_ligne := false;
    distance := round(dist)::int;
    motif := 'Vous avez quitte la ferme (' || round(dist)::text || ' m)';
    return next; return;
  end if;

  en_ligne := true;
  distance := round(dist)::int;
  motif := 'Present';
  return next;
end $$;

-- ── 2. Le téléphone se tait ──────────────────────────────────────────
-- Application tuée, GPS coupé, batterie vide : au bout de 30 minutes
-- sans position, on ferme. Le pointage cesse d'être un chèque en blanc.
create or replace function public.fermer_pointages_silencieux(
  p_minutes integer default 30
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare n integer;
begin
  with concernes as (
    select p.id, p.debut,
           coalesce(p.derniere_verif, p.debut) as dernier_signe
      from public.pointages p
      join public.profils pr on pr.id = p.profil_id
      join public.fermes  f  on f.id  = p.ferme_id
     where p.statut = 'en_cours'
       and pr.role = 'fermier'
       and f.latitude is not null
       and coalesce(p.derniere_verif, p.debut)
             < now() - make_interval(mins => p_minutes)
  )
  update public.pointages p
     set fin = c.dernier_signe,
         duree = greatest(0,
           extract(epoch from (c.dernier_signe - p.debut))::int),
         statut = 'termine',
         sortie_auto = true,
         motif_sortie = 'Plus de nouvelles du telephone depuis '
                        || p_minutes::text || ' minutes'
    from concernes c
   where p.id = c.id;

  get diagnostics n = row_count;
  return n;
end $$;

revoke all on function public.confirmer_presence(double precision, double precision)
  from public, anon;
revoke all on function public.fermer_pointages_silencieux(integer)
  from public, anon;
grant execute on function public.confirmer_presence(double precision, double precision)
  to authenticated;
grant execute on function public.fermer_pointages_silencieux(integer)
  to authenticated;

-- ── Contrôle ─────────────────────────────────────────────────────────
select 'Colonnes de suivi continu' as verification,
  case when (select count(*) from information_schema.columns
    where table_schema='public' and table_name='pointages'
      and column_name in ('derniere_verif','derniere_distance','motif_sortie')) = 3
  then 'ajoutees  OK' else 'INCOMPLETES  ECHEC' end as resultat
union all
select 'Verification de presence',
  case when exists (select 1 from pg_proc p join pg_namespace n
      on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='confirmer_presence')
  then 'en place  OK' else 'ABSENTE  ECHEC' end
union all
select 'Fermeture des pointages muets',
  case when exists (select 1 from pg_proc p join pg_namespace n
      on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='fermer_pointages_silencieux')
  then 'en place  OK' else 'ABSENTE  ECHEC' end
union all
select 'Essai a blanc (0 attendu si personne en ligne)',
  public.fermer_pointages_silencieux(30)::text || ' pointage(s) ferme(s)';
