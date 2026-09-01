-- =====================================================================
-- IDIAMA AGRO — Santé du cheptel : mortalité et vaccins
-- À lancer après 01, 02 et 03. Relançable sans risque.
--
-- Trois idées :
--   1. nb_poules devient l'effectif MIS EN PLACE (les poussins du départ) ;
--      l'effectif vivant se recalcule en retranchant les morts déclarées.
--   2. La date de mise en place donne l'âge du lot. Sans elle, un taux de
--      ponte ne veut rien dire : 75 % est excellent à 70 semaines et
--      catastrophique à 28.
--   3. Le calendrier vaccinal se déduit de cet âge — pas besoin de le
--      saisir, il suffit de cocher ce qui a été fait.
-- =====================================================================

-- ── L'effectif de départ et l'âge du lot ─────────────────────────────
alter table public.batiments
  add column if not exists date_mise_en_place date;

-- ── 1. MORTALITÉ ─────────────────────────────────────────────────────
-- En élevage de pondeuses, la mortalité quotidienne est le premier
-- signal d'alerte : elle monte avant que la ponte ne chute. Une ferme
-- qui ne la compte pas découvre la maladie trois jours trop tard.
--
-- Volontairement PAS de validation par le gérant : une mort constatée
-- est un fait, pas une écriture comptable. La faire attendre deux jours
-- annulerait tout l'intérêt de l'alerte.
create table if not exists public.mortalites (
  id           uuid primary key default gen_random_uuid(),
  ferme_id     uuid not null references public.fermes(id) on delete cascade,
  batiment_id  uuid not null references public.batiments(id) on delete cascade,
  auteur_id    uuid not null references public.profils(id) on delete cascade,
  role_auteur  text not null default 'fermier',
  date         date not null default current_date,
  nombre       integer not null default 0,
  cause        text default 'inconnue',
  note         text default '',
  photos       jsonb not null default '[]'::jsonb,
  cree_le      timestamptz not null default now(),
  -- Un bâtiment, un jour, une seule ligne : on corrige au lieu d'ajouter.
  unique (batiment_id, date)
);

create index if not exists idx_mortalites_ferme
  on public.mortalites(ferme_id, date desc);

-- ── 2. VACCINS FAITS ─────────────────────────────────────────────────
-- On n'enregistre que ce qui a été RÉELLEMENT administré. Le calendrier
-- prévisionnel, lui, se calcule dans l'application à partir de l'âge du
-- lot : rien à saisir, rien à maintenir.
create table if not exists public.vaccinations (
  id           uuid primary key default gen_random_uuid(),
  ferme_id     uuid not null references public.fermes(id) on delete cascade,
  batiment_id  uuid not null references public.batiments(id) on delete cascade,
  auteur_id    uuid not null references public.profils(id) on delete cascade,
  role_auteur  text not null default 'fermier',
  vaccin       text not null,
  age_jours    integer not null default 0,
  date_faite   date not null default current_date,
  note         text default '',
  photos       jsonb not null default '[]'::jsonb,
  cree_le      timestamptz not null default now(),
  unique (batiment_id, vaccin, age_jours)
);

create index if not exists idx_vaccinations_ferme
  on public.vaccinations(ferme_id, date_faite desc);

-- ── Protection ───────────────────────────────────────────────────────
alter table public.mortalites   enable row level security;
alter table public.vaccinations enable row level security;

do $$
declare r record;
begin
  for r in select tablename, policyname from pg_policies
            where schemaname = 'public'
              and tablename in ('mortalites','vaccinations')
  loop
    execute format('drop policy %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;

create policy mort_lecture on public.mortalites for select to authenticated
  using (public.ma_ferme_est(ferme_id));
create policy mort_creation on public.mortalites for insert to authenticated
  with check (public.est_actif() and auteur_id = auth.uid()
              and public.ma_ferme_est(ferme_id));
create policy mort_maj on public.mortalites for update to authenticated
  using (public.est_actif() and public.ma_ferme_est(ferme_id))
  with check (public.ma_ferme_est(ferme_id));
create policy mort_suppr on public.mortalites for delete to authenticated
  using (public.ma_ferme_est(ferme_id)
         and public.mon_role() in ('admin','gerant'));

create policy vacc_lecture on public.vaccinations for select to authenticated
  using (public.ma_ferme_est(ferme_id));
create policy vacc_creation on public.vaccinations for insert to authenticated
  with check (public.est_actif() and auteur_id = auth.uid()
              and public.ma_ferme_est(ferme_id));
create policy vacc_maj on public.vaccinations for update to authenticated
  using (public.est_actif() and public.ma_ferme_est(ferme_id))
  with check (public.ma_ferme_est(ferme_id));
create policy vacc_suppr on public.vaccinations for delete to authenticated
  using (public.ma_ferme_est(ferme_id)
         and public.mon_role() in ('admin','gerant'));

revoke all on public.mortalites   from anon;
revoke all on public.vaccinations from anon;
grant select, insert, update, delete on public.mortalites   to authenticated;
grant select, insert, update, delete on public.vaccinations to authenticated;

-- ── Contrôle ─────────────────────────────────────────────────────────
select
  'Date de mise en place des batiments' as verification,
  case when exists (select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'batiments'
      and column_name = 'date_mise_en_place')
  then 'ajoutee  OK' else 'ABSENTE  ECHEC' end as resultat
union all
select 'Table mortalites',
  case when exists (select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'mortalites')
  then 'creee  OK' else 'ABSENTE  ECHEC' end
union all
select 'Table vaccinations',
  case when exists (select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'vaccinations')
  then 'creee  OK' else 'ABSENTE  ECHEC' end
union all
select 'Les deux tables protegees',
  (select count(*)::text from pg_tables
    where schemaname = 'public' and rowsecurity = true
      and tablename in ('mortalites','vaccinations'))
  || ' sur 2'
  || case when (select count(*) from pg_tables
        where schemaname = 'public' and rowsecurity = true
          and tablename in ('mortalites','vaccinations')) = 2
     then '  OK' else '  ECHEC' end
union all
select 'Regles d''acces',
  (select count(*)::text from pg_policies
    where schemaname = 'public'
      and tablename in ('mortalites','vaccinations'))
  || ' regle(s)'
  || case when (select count(*) from pg_policies
        where schemaname = 'public'
          and tablename in ('mortalites','vaccinations')) = 8
     then '  OK' else '  ECHEC' end
union all
select 'Aucune porte pour les visiteurs',
  (select count(*)::text from information_schema.role_table_grants
    where table_schema = 'public' and grantee = 'anon'
      and table_name in ('mortalites','vaccinations'))
  || ' porte(s)'
  || case when not exists (select 1 from information_schema.role_table_grants
        where table_schema = 'public' and grantee = 'anon'
          and table_name in ('mortalites','vaccinations'))
     then '  OK' else '  ECHEC' end;
