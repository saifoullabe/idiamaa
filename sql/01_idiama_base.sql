-- =====================================================================
-- IDIAMA AGRO — Base de données complète
-- À coller dans Supabase → SQL Editor → Run
-- Le fichier peut être relancé autant de fois qu'on veut : il ne casse rien.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- =====================================================================
-- 1. TABLES
-- =====================================================================

create table if not exists public.fermes (
  id            uuid primary key default gen_random_uuid(),
  nom           text not null,
  adresse       text default '',
  ville         text default '',
  statut        text not null default 'Actif',   -- Actif | Suspendue | Maintenance | Fermé
  gerant_id     uuid,
  prix_alveole  bigint not null default 22000,
  notes         text default '',
  cree_le       timestamptz not null default now()
);

create table if not exists public.profils (
  id            uuid primary key references auth.users(id) on delete cascade,
  login         text unique not null,
  nom           text not null default '',
  prenom        text not null default '',
  role          text not null default 'fermier',  -- admin | gerant | fermier
  ferme_id      uuid references public.fermes(id) on delete set null,
  tel           text default '',
  tel2          text default '',
  date_naissance date,
  lieu_naissance text default '',
  pere          text default '',
  mere          text default '',
  quartier      text default '',
  commune       text default '',
  date_embauche date,
  salaire       bigint default 0,
  notes         text default '',
  photo_url     text,
  piece_url     text,
  contrat_url   text,
  suspendu      boolean not null default false,
  cree_le       timestamptz not null default now()
);

create table if not exists public.batiments (
  id          uuid primary key default gen_random_uuid(),
  ferme_id    uuid not null references public.fermes(id) on delete cascade,
  nom         text not null,
  type        text not null default 'Pondeuses',
  nb_poules   integer not null default 0,
  prix_alveole bigint not null default 22000,
  surface     integer default 0,
  etat        text not null default 'Bon',      -- Bon | Correct | Mauvais
  cree_le     timestamptz not null default now()
);

create table if not exists public.recettes (
  id           uuid primary key default gen_random_uuid(),
  ferme_id     uuid not null references public.fermes(id) on delete cascade,
  auteur_id    uuid not null references public.profils(id) on delete cascade,
  role_auteur  text not null default 'fermier',
  produit      text not null default '',
  quantite     numeric default 0,
  prix_unitaire bigint default 0,
  montant      bigint not null default 0,
  description  text default '',
  date         date not null default current_date,
  statut       text not null default 'attente_gerant', -- attente_gerant | attente_admin | valide | rejete
  motif_rejet  text default '',
  cree_le      timestamptz not null default now()
);

create table if not exists public.depenses (
  id           uuid primary key default gen_random_uuid(),
  ferme_id     uuid not null references public.fermes(id) on delete cascade,
  auteur_id    uuid not null references public.profils(id) on delete cascade,
  role_auteur  text not null default 'fermier',
  categorie    text not null default 'autre',   -- aliment | medicament | batiment | salaire | autre
  article      text not null default '',
  quantite     numeric default 0,
  unite        text default '',
  prix_unitaire bigint default 0,
  montant      bigint not null default 0,
  description  text default '',
  date         date not null default current_date,
  statut       text not null default 'attente_gerant',
  motif_rejet  text default '',
  cree_le      timestamptz not null default now()
);

create table if not exists public.productions (
  id           uuid primary key default gen_random_uuid(),
  ferme_id     uuid not null references public.fermes(id) on delete cascade,
  batiment_id  uuid not null references public.batiments(id) on delete cascade,
  auteur_id    uuid not null references public.profils(id) on delete cascade,
  role_auteur  text not null default 'fermier',
  date         date not null default current_date,
  nb_alveoles  integer not null default 0,
  oeufs        integer not null default 0,
  valeur       bigint not null default 0,
  statut       text not null default 'attente_gerant',
  motif_rejet  text default '',
  cree_le      timestamptz not null default now(),
  -- Un bâtiment, un jour, une seule ligne : sinon le gérant qui ressaisit
  -- après son fermier ferait compter les mêmes oeufs deux fois.
  unique (batiment_id, date)
);

create table if not exists public.depots (
  id           uuid primary key default gen_random_uuid(),
  ferme_id     uuid not null references public.fermes(id) on delete cascade,
  auteur_id    uuid not null references public.profils(id) on delete cascade,
  role_auteur  text not null default 'gerant',
  montant      bigint not null default 0,
  date         date not null default current_date,
  reference    text default '',
  motif        text default '',
  fichiers     jsonb not null default '[]'::jsonb,
  statut       text not null default 'attente_admin',
  motif_rejet  text default '',
  cree_le      timestamptz not null default now()
);

create table if not exists public.pointages (
  id           uuid primary key default gen_random_uuid(),
  profil_id    uuid not null references public.profils(id) on delete cascade,
  ferme_id     uuid references public.fermes(id) on delete cascade,
  debut        timestamptz not null default now(),
  fin          timestamptz,
  duree        integer,                          -- secondes
  statut       text not null default 'en_cours'  -- en_cours | termine
);

create table if not exists public.stocks (
  id           uuid primary key default gen_random_uuid(),
  ferme_id     uuid not null references public.fermes(id) on delete cascade,
  nom          text not null,
  categorie    text not null default 'autre',
  unite        text not null default 'kg',
  quantite     numeric not null default 0,
  seuil_min    numeric not null default 0,
  note         text default '',
  cree_le      timestamptz not null default now()
);

create table if not exists public.mouvements_stock (
  id           uuid primary key default gen_random_uuid(),
  stock_id     uuid not null references public.stocks(id) on delete cascade,
  ferme_id     uuid not null references public.fermes(id) on delete cascade,
  auteur_id    uuid not null references public.profils(id) on delete cascade,
  role_auteur  text not null default 'fermier',
  type         text not null default 'entree',   -- entree | sortie
  quantite     numeric not null default 0,
  unite        text default '',
  note         text default '',
  cree_le      timestamptz not null default now()
);

create table if not exists public.signalements (
  id           uuid primary key default gen_random_uuid(),
  ferme_id     uuid not null references public.fermes(id) on delete cascade,
  auteur_id    uuid not null references public.profils(id) on delete cascade,
  batiment_id  uuid references public.batiments(id) on delete set null,
  titre        text not null,
  priorite     text not null default 'normal',   -- urgent | normal | info
  description  text default '',
  date         date not null default current_date,
  statut       text not null default 'ouvert',   -- ouvert | traite
  reponse      text default '',
  cree_le      timestamptz not null default now()
);

create table if not exists public.rapports (
  id           uuid primary key default gen_random_uuid(),
  ferme_id     uuid not null references public.fermes(id) on delete cascade,
  auteur_id    uuid not null references public.profils(id) on delete cascade,
  titre        text not null,
  activites    text default '',
  observations text default '',
  date         date not null default current_date,
  cree_le      timestamptz not null default now()
);

create table if not exists public.articles_perso (
  id           uuid primary key default gen_random_uuid(),
  ferme_id     uuid references public.fermes(id) on delete cascade,
  categorie    text not null,
  nom          text not null,
  cree_le      timestamptz not null default now(),
  unique (ferme_id, categorie, nom)
);

-- Lien gérant -> ferme (après création de profils)
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'fermes_gerant_fk') then
    alter table public.fermes
      add constraint fermes_gerant_fk
      foreign key (gerant_id) references public.profils(id) on delete set null;
  end if;
end $$;

create index if not exists idx_recettes_ferme     on public.recettes(ferme_id, date desc);
create index if not exists idx_depenses_ferme     on public.depenses(ferme_id, date desc);
create index if not exists idx_productions_ferme  on public.productions(ferme_id, date desc);
create index if not exists idx_depots_ferme       on public.depots(ferme_id, date desc);
create index if not exists idx_pointages_profil   on public.pointages(profil_id, debut desc);
create index if not exists idx_pointages_encours  on public.pointages(statut) where statut = 'en_cours';
create index if not exists idx_profils_ferme      on public.profils(ferme_id);

-- =====================================================================
-- 2. FONCTIONS D'IDENTITÉ (la seule source de vérité = auth.uid())
-- =====================================================================

create or replace function public.mon_role()
returns text
language sql
stable
security definer
set search_path = public
as $$ select role from public.profils where id = auth.uid() $$;

create or replace function public.ma_ferme()
returns uuid
language sql
stable
security definer
set search_path = public
as $$ select ferme_id from public.profils where id = auth.uid() $$;

create or replace function public.est_actif()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select not suspendu
       and (ferme_id is null
            or role = 'admin'
            or (select statut from public.fermes f where f.id = p.ferme_id) <> 'Suspendue')
     from public.profils p where p.id = auth.uid()),
    false)
$$;

-- Est-ce que je peux voir/toucher cette ferme ?
create or replace function public.ma_ferme_est(cible uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$ select public.mon_role() = 'admin' or cible = public.ma_ferme() $$;

revoke all on function public.mon_role()      from public, anon;
revoke all on function public.ma_ferme()      from public, anon;
revoke all on function public.est_actif()     from public, anon;
revoke all on function public.ma_ferme_est(uuid) from public, anon;
grant execute on function public.mon_role()      to authenticated;
grant execute on function public.ma_ferme()      to authenticated;
grant execute on function public.est_actif()     to authenticated;
grant execute on function public.ma_ferme_est(uuid) to authenticated;

-- =====================================================================
-- 3. LE RÔLE NE PEUT PAS S'ÉCHAPPER
--    Personne, sauf un admin, ne peut changer son propre rôle,
--    sa ferme, sa suspension ou son identifiant.
-- =====================================================================

create or replace function public.profils_protege()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.mon_role() = 'admin' then
    return new;
  end if;
  new.role     := old.role;
  new.ferme_id := old.ferme_id;
  new.suspendu := old.suspendu;
  new.login    := old.login;
  new.salaire  := old.salaire;
  return new;
end $$;

drop trigger if exists trg_profils_protege on public.profils;
create trigger trg_profils_protege
  before update on public.profils
  for each row execute function public.profils_protege();

-- =====================================================================
-- 4. RLS — on efface d'abord TOUTES les anciennes règles par leur vrai nom
-- =====================================================================

do $$
declare r record;
begin
  for r in
    select schemaname, tablename, policyname
      from pg_policies
     where schemaname = 'public'
       and tablename in ('fermes','profils','batiments','recettes','depenses',
                         'productions','depots','pointages','stocks',
                         'mouvements_stock','signalements','rapports','articles_perso')
  loop
    execute format('drop policy %I on %I.%I', r.policyname, r.schemaname, r.tablename);
  end loop;
end $$;

alter table public.fermes           enable row level security;
alter table public.profils          enable row level security;
alter table public.batiments        enable row level security;
alter table public.recettes         enable row level security;
alter table public.depenses         enable row level security;
alter table public.productions      enable row level security;
alter table public.depots           enable row level security;
alter table public.pointages        enable row level security;
alter table public.stocks           enable row level security;
alter table public.mouvements_stock enable row level security;
alter table public.signalements     enable row level security;
alter table public.rapports         enable row level security;
alter table public.articles_perso   enable row level security;

-- ── FERMES ──
create policy fermes_lecture on public.fermes for select to authenticated
  using (true);
create policy fermes_ecriture on public.fermes for insert to authenticated
  with check (public.mon_role() = 'admin');
create policy fermes_maj on public.fermes for update to authenticated
  using (public.mon_role() = 'admin') with check (public.mon_role() = 'admin');
create policy fermes_suppr on public.fermes for delete to authenticated
  using (public.mon_role() = 'admin');

-- ── PROFILS ──
create policy profils_lecture on public.profils for select to authenticated
  using (
    id = auth.uid()
    or public.mon_role() = 'admin'
    or (public.mon_role() = 'gerant' and ferme_id = public.ma_ferme())
  );
create policy profils_creation on public.profils for insert to authenticated
  with check (public.mon_role() = 'admin');
create policy profils_maj on public.profils for update to authenticated
  using (id = auth.uid() or public.mon_role() = 'admin')
  with check (id = auth.uid() or public.mon_role() = 'admin');
create policy profils_suppr on public.profils for delete to authenticated
  using (public.mon_role() = 'admin');

-- ── BÂTIMENTS ──
create policy batiments_lecture on public.batiments for select to authenticated
  using (public.ma_ferme_est(ferme_id));
create policy batiments_creation on public.batiments for insert to authenticated
  with check (public.est_actif() and public.ma_ferme_est(ferme_id) and public.mon_role() in ('admin','gerant'));
create policy batiments_maj on public.batiments for update to authenticated
  using (public.ma_ferme_est(ferme_id) and public.mon_role() in ('admin','gerant'))
  with check (public.ma_ferme_est(ferme_id) and public.mon_role() in ('admin','gerant'));
create policy batiments_suppr on public.batiments for delete to authenticated
  using (public.ma_ferme_est(ferme_id) and public.mon_role() in ('admin','gerant'));

-- ── RECETTES / DÉPENSES / PRODUCTIONS / DÉPÔTS : même logique ──
create policy recettes_lecture on public.recettes for select to authenticated
  using (public.ma_ferme_est(ferme_id));
create policy recettes_creation on public.recettes for insert to authenticated
  with check (public.est_actif() and auteur_id = auth.uid() and public.ma_ferme_est(ferme_id));
create policy recettes_maj on public.recettes for update to authenticated
  using (public.est_actif() and public.ma_ferme_est(ferme_id)
         and (public.mon_role() in ('admin','gerant') or (auteur_id = auth.uid() and statut like 'attente%')))
  with check (public.ma_ferme_est(ferme_id));
create policy recettes_suppr on public.recettes for delete to authenticated
  using (public.est_actif() and public.ma_ferme_est(ferme_id)
         and (public.mon_role() in ('admin','gerant') or (auteur_id = auth.uid() and statut like 'attente%')));

create policy depenses_lecture on public.depenses for select to authenticated
  using (public.ma_ferme_est(ferme_id));
create policy depenses_creation on public.depenses for insert to authenticated
  with check (public.est_actif() and auteur_id = auth.uid() and public.ma_ferme_est(ferme_id));
create policy depenses_maj on public.depenses for update to authenticated
  using (public.est_actif() and public.ma_ferme_est(ferme_id)
         and (public.mon_role() in ('admin','gerant') or (auteur_id = auth.uid() and statut like 'attente%')))
  with check (public.ma_ferme_est(ferme_id));
create policy depenses_suppr on public.depenses for delete to authenticated
  using (public.est_actif() and public.ma_ferme_est(ferme_id)
         and (public.mon_role() in ('admin','gerant') or (auteur_id = auth.uid() and statut like 'attente%')));

create policy productions_lecture on public.productions for select to authenticated
  using (public.ma_ferme_est(ferme_id));
create policy productions_creation on public.productions for insert to authenticated
  with check (public.est_actif() and auteur_id = auth.uid() and public.ma_ferme_est(ferme_id));
create policy productions_maj on public.productions for update to authenticated
  using (public.est_actif() and public.ma_ferme_est(ferme_id)
         and (public.mon_role() in ('admin','gerant') or (auteur_id = auth.uid() and statut like 'attente%')))
  with check (public.ma_ferme_est(ferme_id));
create policy productions_suppr on public.productions for delete to authenticated
  using (public.est_actif() and public.ma_ferme_est(ferme_id)
         and (public.mon_role() in ('admin','gerant') or (auteur_id = auth.uid() and statut like 'attente%')));

create policy depots_lecture on public.depots for select to authenticated
  using (public.ma_ferme_est(ferme_id));
create policy depots_creation on public.depots for insert to authenticated
  with check (public.est_actif() and auteur_id = auth.uid() and public.ma_ferme_est(ferme_id));
create policy depots_maj on public.depots for update to authenticated
  using (public.est_actif() and public.ma_ferme_est(ferme_id)
         and (public.mon_role() in ('admin','gerant') or (auteur_id = auth.uid() and statut like 'attente%')))
  with check (public.ma_ferme_est(ferme_id));
create policy depots_suppr on public.depots for delete to authenticated
  using (public.est_actif() and public.ma_ferme_est(ferme_id)
         and (public.mon_role() = 'admin' or (auteur_id = auth.uid() and statut like 'attente%')));

-- ── POINTAGES ──
create policy pointages_lecture on public.pointages for select to authenticated
  using (profil_id = auth.uid() or public.ma_ferme_est(ferme_id));
create policy pointages_creation on public.pointages for insert to authenticated
  with check (public.est_actif() and profil_id = auth.uid());
create policy pointages_maj on public.pointages for update to authenticated
  using (profil_id = auth.uid() or public.mon_role() = 'admin')
  with check (profil_id = auth.uid() or public.mon_role() = 'admin');
create policy pointages_suppr on public.pointages for delete to authenticated
  using (public.mon_role() = 'admin');

-- ── STOCKS ──
create policy stocks_lecture on public.stocks for select to authenticated
  using (public.ma_ferme_est(ferme_id));
create policy stocks_creation on public.stocks for insert to authenticated
  with check (public.est_actif() and public.ma_ferme_est(ferme_id));
create policy stocks_maj on public.stocks for update to authenticated
  using (public.est_actif() and public.ma_ferme_est(ferme_id))
  with check (public.ma_ferme_est(ferme_id));
create policy stocks_suppr on public.stocks for delete to authenticated
  using (public.ma_ferme_est(ferme_id) and public.mon_role() in ('admin','gerant'));

create policy mouv_lecture on public.mouvements_stock for select to authenticated
  using (public.ma_ferme_est(ferme_id));
create policy mouv_creation on public.mouvements_stock for insert to authenticated
  with check (public.est_actif() and auteur_id = auth.uid() and public.ma_ferme_est(ferme_id));

-- ── SIGNALEMENTS ──
create policy sig_lecture on public.signalements for select to authenticated
  using (public.ma_ferme_est(ferme_id));
create policy sig_creation on public.signalements for insert to authenticated
  with check (public.est_actif() and auteur_id = auth.uid() and public.ma_ferme_est(ferme_id));
create policy sig_maj on public.signalements for update to authenticated
  using (public.est_actif() and public.ma_ferme_est(ferme_id))
  with check (public.ma_ferme_est(ferme_id));
create policy sig_suppr on public.signalements for delete to authenticated
  using (public.ma_ferme_est(ferme_id) and public.mon_role() in ('admin','gerant'));

-- ── RAPPORTS ──
create policy rap_lecture on public.rapports for select to authenticated
  using (public.ma_ferme_est(ferme_id));
create policy rap_creation on public.rapports for insert to authenticated
  with check (public.est_actif() and auteur_id = auth.uid() and public.ma_ferme_est(ferme_id));
create policy rap_maj on public.rapports for update to authenticated
  using (public.est_actif() and (auteur_id = auth.uid() or public.mon_role() in ('admin','gerant')))
  with check (public.ma_ferme_est(ferme_id));
create policy rap_suppr on public.rapports for delete to authenticated
  using (auteur_id = auth.uid() or public.mon_role() in ('admin','gerant'));

-- ── ARTICLES PERSONNALISÉS ──
create policy art_lecture on public.articles_perso for select to authenticated
  using (ferme_id is null or public.ma_ferme_est(ferme_id));
create policy art_creation on public.articles_perso for insert to authenticated
  with check (public.est_actif() and (ferme_id is null or public.ma_ferme_est(ferme_id)));
create policy art_suppr on public.articles_perso for delete to authenticated
  using (public.mon_role() in ('admin','gerant'));

-- =====================================================================
-- 5. AUCUN ACCÈS POUR LES VISITEURS NON CONNECTÉS
-- =====================================================================
do $$
declare t text;
begin
  foreach t in array array['fermes','profils','batiments','recettes','depenses',
                           'productions','depots','pointages','stocks',
                           'mouvements_stock','signalements','rapports','articles_perso']
  loop
    execute format('revoke all on public.%I from anon', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
  end loop;
end $$;

-- =====================================================================
-- 6. STOCKAGE DES PHOTOS ET REÇUS
-- =====================================================================
insert into storage.buckets (id, name, public)
values ('documents', 'documents', true)
on conflict (id) do nothing;

do $$
declare r record;
begin
  for r in select policyname from pg_policies
            where schemaname = 'storage' and tablename = 'objects'
              and policyname like 'idiama_%'
  loop
    execute format('drop policy %I on storage.objects', r.policyname);
  end loop;
end $$;

create policy idiama_docs_lecture on storage.objects for select to authenticated
  using (bucket_id = 'documents');
create policy idiama_docs_depot on storage.objects for insert to authenticated
  with check (bucket_id = 'documents');
create policy idiama_docs_maj on storage.objects for update to authenticated
  using (bucket_id = 'documents');
create policy idiama_docs_suppr on storage.objects for delete to authenticated
  using (bucket_id = 'documents' and public.mon_role() in ('admin','gerant'));

-- =====================================================================
-- 5 bis. LES COLLÈGUES
--   Un fermier doit pouvoir lire le nom de ses collègues sans voir
--   leur salaire ni leur filiation. Cette vue ne montre que l'utile.
-- =====================================================================
drop view if exists public.collegues;
create view public.collegues
with (security_invoker = off) as
select p.id, p.nom, p.prenom, p.role, p.ferme_id,
       p.photo_url, p.tel, p.suspendu, p.cree_le, p.login
  from public.profils p
 where p.id = auth.uid()
    or public.mon_role() = 'admin'
    or (p.ferme_id is not null and p.ferme_id = public.ma_ferme());

revoke all on public.collegues from anon, public;
grant select on public.collegues to authenticated;

-- =====================================================================
-- 6 bis. MOUVEMENT DE STOCK
--   Entrée et sortie passent par ici : la quantité et la trace du
--   mouvement bougent ensemble, et on ne peut pas sortir plus que ce
--   qu'il y a dans le magasin.
-- =====================================================================
create or replace function public.bouger_stock(
  p_stock uuid,
  p_type  text,
  p_qte   numeric,
  p_note  text default ''
)
returns numeric
language plpgsql
security definer
set search_path = public
as $$
declare
  s public.stocks%rowtype;
  moi public.profils%rowtype;
  nouvelle numeric;
begin
  select * into moi from public.profils where id = auth.uid();
  if moi.id is null then raise exception 'Connexion requise'; end if;
  if moi.suspendu then raise exception 'Compte suspendu'; end if;

  select * into s from public.stocks where id = p_stock;
  if s.id is null then raise exception 'Stock introuvable'; end if;

  if moi.role <> 'admin' and s.ferme_id <> moi.ferme_id then
    raise exception 'Ce stock n''est pas celui de votre ferme';
  end if;

  if p_qte is null or p_qte <= 0 then raise exception 'Quantité invalide'; end if;

  if p_type = 'sortie' then
    if p_qte > s.quantite then
      raise exception 'Stock insuffisant : % % disponibles', s.quantite, s.unite;
    end if;
    nouvelle := s.quantite - p_qte;
  else
    nouvelle := s.quantite + p_qte;
  end if;

  update public.stocks set quantite = nouvelle where id = p_stock;

  insert into public.mouvements_stock
    (stock_id, ferme_id, auteur_id, role_auteur, type, quantite, unite, note)
  values (p_stock, s.ferme_id, moi.id, moi.role, p_type, p_qte, s.unite, coalesce(p_note,''));

  return nouvelle;
end $$;

revoke all on function public.bouger_stock(uuid, text, numeric, text) from public, anon;
grant execute on function public.bouger_stock(uuid, text, numeric, text) to authenticated;

-- =====================================================================
-- 7. CONTRÔLE — ce que le fichier vient de faire
-- =====================================================================
create or replace function public.idiama_controle()
returns table (verification text, resultat text)
language plpgsql
security definer
set search_path = public
as $$
declare n int;
begin
  select count(*) into n from information_schema.tables
   where table_schema = 'public'
     and table_name in ('fermes','profils','batiments','recettes','depenses',
                        'productions','depots','pointages','stocks',
                        'mouvements_stock','signalements','rapports','articles_perso');
  verification := 'Tables créées (13 attendues)';
  resultat := n || ' trouvée(s)' || case when n = 13 then '  ✅' else '  ❌' end;
  return next;

  select count(*) into n from pg_tables t
   where t.schemaname = 'public' and t.rowsecurity = true
     and t.tablename in ('fermes','profils','batiments','recettes','depenses',
                         'productions','depots','pointages','stocks',
                         'mouvements_stock','signalements','rapports','articles_perso');
  verification := 'Tables protégées par RLS (13 attendues)';
  resultat := n || ' protégée(s)' || case when n = 13 then '  ✅' else '  ❌' end;
  return next;

  select count(*) into n from pg_policies where schemaname = 'public';
  verification := 'Règles d''accès posées';
  resultat := n || ' règle(s)' || case when n >= 40 then '  ✅' else '  ❌' end;
  return next;

  select count(*) into n
    from information_schema.role_table_grants
   where table_schema = 'public' and grantee = 'anon'
     and table_name in ('fermes','profils','batiments','recettes','depenses',
                        'productions','depots','pointages','stocks',
                        'mouvements_stock','signalements','rapports','articles_perso');
  verification := 'Portes ouvertes aux visiteurs (0 attendu)';
  resultat := n || ' porte(s)' || case when n = 0 then '  ✅' else '  ❌' end;
  return next;

  select count(*) into n from pg_trigger
   where tgname = 'trg_profils_protege' and not tgisinternal;
  verification := 'Verrou anti-changement de rôle';
  resultat := case when n = 1 then 'en place  ✅' else 'ABSENT  ❌' end;
  return next;

  select count(*) into n from storage.buckets where id = 'documents';
  verification := 'Espace photos et reçus';
  resultat := case when n = 1 then 'créé  ✅' else 'ABSENT  ❌' end;
  return next;
end $$;

select * from public.idiama_controle();
