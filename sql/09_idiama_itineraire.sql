-- =====================================================================
-- IDIAMA AGRO — Sortie de zone : alerte et itinéraire
-- À lancer après 08. Relançable sans risque.
--
-- Quand un fermier quitte la ferme pendant son service :
--   1. il est mis hors ligne (déjà fait par confirmer_presence) ;
--   2. la sortie est inscrite dans un journal que l'admin consulte ;
--   3. son trajet est enregistré, MAIS PAS INDÉFINIMENT.
--
-- ⚠ Le suivi s'arrête automatiquement 2 heures après la sortie.
--   Suivre quelqu'un pendant son service se défend ; le suivre le soir
--   chez lui, non — et aucun réglage de l'application ne le permet.
--   La limite est posée ici, dans la base, pas dans le téléphone :
--   personne ne peut la contourner en modifiant l'application.
-- =====================================================================

alter table public.pointages
  add column if not exists suivi_jusqua timestamptz;

-- ── Le journal des sorties ───────────────────────────────────────────
create table if not exists public.sorties_zone (
  id           uuid primary key default gen_random_uuid(),
  pointage_id  uuid references public.pointages(id) on delete cascade,
  profil_id    uuid not null references public.profils(id) on delete cascade,
  ferme_id     uuid references public.fermes(id) on delete cascade,
  moment       timestamptz not null default now(),
  latitude     double precision,
  longitude    double precision,
  distance     integer,
  vu_par_admin boolean not null default false
);

create index if not exists idx_sorties_moment
  on public.sorties_zone(moment desc);

-- ── Le trajet, point par point ───────────────────────────────────────
create table if not exists public.trajets (
  id          uuid primary key default gen_random_uuid(),
  pointage_id uuid not null references public.pointages(id) on delete cascade,
  profil_id   uuid not null references public.profils(id) on delete cascade,
  ferme_id    uuid references public.fermes(id) on delete cascade,
  moment      timestamptz not null default now(),
  latitude    double precision not null,
  longitude   double precision not null,
  distance    integer
);

create index if not exists idx_trajets_pointage
  on public.trajets(pointage_id, moment);

alter table public.sorties_zone enable row level security;
alter table public.trajets      enable row level security;

do $$
declare r record;
begin
  for r in select tablename, policyname from pg_policies
            where schemaname='public' and tablename in ('sorties_zone','trajets')
  loop
    execute format('drop policy %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;

-- L'intéressé voit son propre trajet : c'est la moindre des choses,
-- et ça évite qu'il découvre le suivi par hasard.
create policy sortie_lecture on public.sorties_zone for select to authenticated
  using (profil_id = auth.uid() or public.ma_ferme_est(ferme_id));
create policy sortie_maj on public.sorties_zone for update to authenticated
  using (public.mon_role() in ('admin','gerant'))
  with check (public.mon_role() in ('admin','gerant'));
create policy sortie_suppr on public.sorties_zone for delete to authenticated
  using (public.mon_role() = 'admin');

create policy trajet_lecture on public.trajets for select to authenticated
  using (profil_id = auth.uid() or public.ma_ferme_est(ferme_id));
create policy trajet_suppr on public.trajets for delete to authenticated
  using (public.mon_role() = 'admin');

revoke all on public.sorties_zone from anon;
revoke all on public.trajets      from anon;
grant select, update, delete on public.sorties_zone to authenticated;
grant select, delete          on public.trajets      to authenticated;

-- ── confirmer_presence, version complète ─────────────────────────────
-- Elle fait maintenant trois choses de plus : inscrire la sortie au
-- journal, ouvrir la fenêtre de suivi, et déposer les points du trajet.
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

  -- Plus de pointage ouvert : on n'accepte des points que si la fenêtre
  -- de suivi qui a suivi la sortie n'est pas encore refermée.
  if p.id is null then
    select * into p from public.pointages
     where profil_id = moi.id
       and suivi_jusqua is not null
       and suivi_jusqua > now()
     order by debut desc limit 1;

    if p.id is null then
      en_ligne := false; distance := null;
      motif := 'Aucun suivi en cours';
      return next; return;
    end if;

    select * into f from public.fermes where id = p.ferme_id;
    dist := case when f.latitude is null then null
            else public.distance_metres(f.latitude, f.longitude,
                                        p_latitude, p_longitude) end;
    insert into public.trajets
      (pointage_id, profil_id, ferme_id, latitude, longitude, distance)
    values (p.id, moi.id, p.ferme_id, p_latitude, p_longitude,
            case when dist is null then null else round(dist)::int end);

    en_ligne := false;
    distance := case when dist is null then null else round(dist)::int end;
    motif := 'Trajet enregistre';
    return next; return;
  end if;

  select * into f from public.fermes where id = p.ferme_id;

  if f.id is null or f.latitude is null or f.longitude is null
     or moi.role <> 'fermier' then
    update public.pointages set derniere_verif = now() where id = p.id;
    en_ligne := true; distance := null;
    motif := 'Pas de controle sur cette ferme';
    return next; return;
  end if;

  if p_latitude is null or p_longitude is null then
    update public.pointages set derniere_verif = now() where id = p.id;
    en_ligne := true; distance := null;
    motif := 'Position non transmise';
    return next; return;
  end if;

  dist := public.distance_metres(f.latitude, f.longitude,
                                 p_latitude, p_longitude);

  update public.pointages
     set derniere_verif = now(),
         derniere_distance = round(dist)::int
   where id = p.id;

  -- Pendant le service, on garde aussi la trace des déplacements :
  -- c'est le temps de travail, et c'est ce que l'admin a le droit de voir.
  insert into public.trajets
    (pointage_id, profil_id, ferme_id, latitude, longitude, distance)
  values (p.id, moi.id, p.ferme_id, p_latitude, p_longitude,
          round(dist)::int);

  if dist > f.rayon_metres then
    update public.pointages
       set fin = now(),
           duree = greatest(0, extract(epoch from (now() - debut))::int),
           statut = 'termine',
           lat_sortie = p_latitude,
           lon_sortie = p_longitude,
           sortie_auto = true,
           motif_sortie = 'Sorti de la zone (' || round(dist)::text || ' m)',
           -- La fenêtre de suivi : 2 heures, pas une de plus.
           suivi_jusqua = now() + interval '2 hours'
     where id = p.id;

    insert into public.sorties_zone
      (pointage_id, profil_id, ferme_id, latitude, longitude, distance)
    values (p.id, moi.id, p.ferme_id, p_latitude, p_longitude,
            round(dist)::int);

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

revoke all on function public.confirmer_presence(double precision, double precision)
  from public, anon;
grant execute on function public.confirmer_presence(double precision, double precision)
  to authenticated;

-- ── Contrôle ─────────────────────────────────────────────────────────
select 'Journal des sorties' as verification,
  case when exists (select 1 from information_schema.tables
    where table_schema='public' and table_name='sorties_zone')
  then 'cree  OK' else 'ABSENT  ECHEC' end as resultat
union all
select 'Table des trajets',
  case when exists (select 1 from information_schema.tables
    where table_schema='public' and table_name='trajets')
  then 'creee  OK' else 'ABSENTE  ECHEC' end
union all
select 'Fenetre de suivi limitee',
  case when exists (select 1 from information_schema.columns
    where table_schema='public' and table_name='pointages'
      and column_name='suivi_jusqua')
  then 'posee  OK' else 'ABSENTE  ECHEC' end
union all
select 'Les deux tables protegees',
  case when (select count(*) from pg_tables where schemaname='public'
    and rowsecurity=true and tablename in ('sorties_zone','trajets')) = 2
  then 'oui  OK' else 'NON  ECHEC' end
union all
select 'Personne ne peut ecrire un faux trajet',
  case when not exists (select 1 from pg_policies
    where schemaname='public' and tablename='trajets' and cmd = 'INSERT')
  then 'oui, seule la fonction ecrit  OK' else 'NON  ECHEC' end;
