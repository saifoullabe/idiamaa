-- =====================================================================
-- IDIAMA AGRO — Les photos
-- À lancer après 01 et 02. Relançable sans risque.
--
-- Les images ne sont PAS stockées dans la base : elles partent dans
-- Supabase Storage, et la base ne garde que leur adresse. C'est ce qui
-- permet de les conserver sans alourdir la base ni ralentir l'application.
--
-- Deux façons d'envoyer une photo :
--   1. attachée à un signalement ou à un rapport ;
--   2. seule, dans l'espace « Photos », avec une note.
-- =====================================================================

-- ── 1. Photos attachées ──────────────────────────────────────────────
alter table public.signalements
  add column if not exists photos jsonb not null default '[]'::jsonb;

alter table public.rapports
  add column if not exists photos jsonb not null default '[]'::jsonb;

-- ── 2. Espace Photos ─────────────────────────────────────────────────
create table if not exists public.photos (
  id           uuid primary key default gen_random_uuid(),
  ferme_id     uuid not null references public.fermes(id) on delete cascade,
  auteur_id    uuid not null references public.profils(id) on delete cascade,
  role_auteur  text not null default 'fermier',
  url          text not null,
  note         text default '',
  batiment_id  uuid references public.batiments(id) on delete set null,
  date         date not null default current_date,
  cree_le      timestamptz not null default now()
);

create index if not exists idx_photos_ferme on public.photos(ferme_id, cree_le desc);

alter table public.photos enable row level security;

do $$
declare r record;
begin
  for r in select policyname from pg_policies
            where schemaname = 'public' and tablename = 'photos'
  loop
    execute format('drop policy %I on public.photos', r.policyname);
  end loop;
end $$;

create policy photos_lecture on public.photos for select to authenticated
  using (public.ma_ferme_est(ferme_id));
create policy photos_creation on public.photos for insert to authenticated
  with check (public.est_actif() and auteur_id = auth.uid() and public.ma_ferme_est(ferme_id));
create policy photos_maj on public.photos for update to authenticated
  using (public.est_actif() and (auteur_id = auth.uid() or public.mon_role() in ('admin','gerant')))
  with check (public.ma_ferme_est(ferme_id));
create policy photos_suppr on public.photos for delete to authenticated
  using (auteur_id = auth.uid() or public.mon_role() in ('admin','gerant'));

revoke all on public.photos from anon;
grant select, insert, update, delete on public.photos to authenticated;

-- ── Contrôle ─────────────────────────────────────────────────────────
select
  'Photos sur les signalements' as verification,
  case when exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'signalements'
       and column_name = 'photos'
  ) then 'en place  OK' else 'ABSENT  ECHEC' end as resultat
union all
select
  'Photos sur les rapports',
  case when exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'rapports'
       and column_name = 'photos'
  ) then 'en place  OK' else 'ABSENT  ECHEC' end
union all
select
  'Table de l''espace Photos',
  case when exists (
    select 1 from information_schema.tables
     where table_schema = 'public' and table_name = 'photos'
  ) then 'creee  OK' else 'ABSENTE  ECHEC' end
union all
select
  'Espace Photos protege',
  case when exists (
    select 1 from pg_tables where schemaname = 'public'
       and tablename = 'photos' and rowsecurity = true
  ) then 'protege  OK' else 'NON PROTEGE  ECHEC' end
union all
select
  'Porte ouverte aux visiteurs (0 attendu)',
  (select count(*)::text from information_schema.role_table_grants
    where table_schema = 'public' and grantee = 'anon' and table_name = 'photos')
  || case when not exists (
       select 1 from information_schema.role_table_grants
        where table_schema = 'public' and grantee = 'anon' and table_name = 'photos')
     then '  OK' else '  ECHEC' end
union all
select
  'Espace de stockage des fichiers',
  case when exists (select 1 from storage.buckets where id = 'documents')
    then 'pret  OK' else 'ABSENT  ECHEC' end;
