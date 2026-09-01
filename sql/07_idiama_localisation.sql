-- =====================================================================
-- IDIAMA AGRO — Le pointage n'est possible qu'à la ferme
-- À lancer après 01. Relançable sans risque.
--
-- L'administrateur enregistre la position de chaque ferme et le rayon
-- toléré. Un fermier ne peut passer en ligne que s'il se trouve dans ce
-- cercle ; s'il en sort, l'application le met hors ligne toute seule.
--
-- Seul l'administrateur peut poser ou retirer une position : les règles
-- de la table fermes le garantissent déjà (écriture réservée à l'admin).
-- =====================================================================

alter table public.fermes
  add column if not exists latitude    double precision,
  add column if not exists longitude   double precision,
  add column if not exists rayon_metres integer not null default 300;

-- Où était la personne au moment du pointage, et à quelle distance de
-- la ferme. On garde la trace : c'est la preuve, pas seulement le filtre.
alter table public.pointages
  add column if not exists latitude       double precision,
  add column if not exists longitude      double precision,
  add column if not exists distance_metres integer,
  add column if not exists lat_sortie     double precision,
  add column if not exists lon_sortie     double precision,
  add column if not exists sortie_auto    boolean not null default false;

-- ── La distance entre deux points du globe, en mètres ────────────────
-- Formule de haversine. On la met dans la base pour que le contrôle ne
-- dépende pas de ce que le téléphone veut bien calculer.
create or replace function public.distance_metres(
  lat1 double precision, lon1 double precision,
  lat2 double precision, lon2 double precision
)
returns double precision
language sql
immutable
as $$
  select 6371000 * 2 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2)
    + cos(radians(lat1)) * cos(radians(lat2))
    * power(sin(radians(lon2 - lon1) / 2), 2)
  ))
$$;

-- ── Pointer l'arrivée, avec vérification de la position ──────────────
-- Le contrôle est fait ICI, dans la base. Un téléphone modifié qui
-- appellerait directement l'API se ferait refuser de la même façon.
create or replace function public.pointer_arrivee(
  p_latitude  double precision,
  p_longitude double precision
)
returns table (message text, distance integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  moi  public.profils%rowtype;
  f    public.fermes%rowtype;
  dist double precision;
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
  if moi.role = 'fermier' and f.id is not null
     and f.latitude is not null and f.longitude is not null then
    if p_latitude is null or p_longitude is null then
      raise exception 'Position introuvable. Activez la localisation du téléphone.';
    end if;
    dist := public.distance_metres(f.latitude, f.longitude,
                                   p_latitude, p_longitude);
    if dist > f.rayon_metres then
      raise exception 'Vous êtes à % m de la ferme %. Le pointage n''est possible que sur place (moins de % m).',
        round(dist)::text, f.nom, f.rayon_metres::text;
    end if;
  end if;

  insert into public.pointages
    (profil_id, ferme_id, debut, statut, latitude, longitude, distance_metres)
  values
    (moi.id, moi.ferme_id, now(), 'en_cours',
     p_latitude, p_longitude,
     case when dist is null then null else round(dist)::int end);

  message := 'Arrivée enregistrée';
  distance := case when dist is null then null else round(dist)::int end;
  return next;
end $$;

-- ── Pointer la sortie ────────────────────────────────────────────────
create or replace function public.pointer_sortie(
  p_latitude  double precision default null,
  p_longitude double precision default null,
  p_auto      boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare p public.pointages%rowtype;
begin
  select * into p from public.pointages
   where profil_id = auth.uid() and statut = 'en_cours'
   order by debut desc limit 1;
  if p.id is null then return; end if;

  update public.pointages
     set fin = now(),
         duree = greatest(0, extract(epoch from (now() - debut))::int),
         statut = 'termine',
         lat_sortie = p_latitude,
         lon_sortie = p_longitude,
         sortie_auto = coalesce(p_auto, false)
   where id = p.id;
end $$;

revoke all on function public.pointer_arrivee(double precision, double precision)
  from public, anon;
revoke all on function public.pointer_sortie(double precision, double precision, boolean)
  from public, anon;
revoke all on function public.distance_metres(double precision, double precision, double precision, double precision)
  from public, anon;
grant execute on function public.pointer_arrivee(double precision, double precision)
  to authenticated;
grant execute on function public.pointer_sortie(double precision, double precision, boolean)
  to authenticated;
grant execute on function public.distance_metres(double precision, double precision, double precision, double precision)
  to authenticated;

-- ── Contrôle ─────────────────────────────────────────────────────────
select 'Position sur les fermes' as verification,
  case when (select count(*) from information_schema.columns
    where table_schema='public' and table_name='fermes'
      and column_name in ('latitude','longitude','rayon_metres')) = 3
  then 'ajoutee  OK' else 'INCOMPLETE  ECHEC' end as resultat
union all
select 'Position sur les pointages',
  case when (select count(*) from information_schema.columns
    where table_schema='public' and table_name='pointages'
      and column_name in ('latitude','longitude','distance_metres','sortie_auto')) = 4
  then 'ajoutee  OK' else 'INCOMPLETE  ECHEC' end
union all
select 'Calcul de distance',
  case when exists (select 1 from pg_proc p join pg_namespace n
      on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='distance_metres')
  then 'pret  OK' else 'ABSENT  ECHEC' end
union all
select 'Controle du lieu au pointage',
  case when exists (select 1 from pg_proc p join pg_namespace n
      on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='pointer_arrivee')
  then 'en place  OK' else 'ABSENT  ECHEC' end
union all
select 'Essai : 1 km entre deux points',
  round(public.distance_metres(9.5090, -13.7120, 9.5180, -13.7120))::text
  || ' m (environ 1000 attendus)';
