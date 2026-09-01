-- =====================================================================
-- IDIAMA AGRO — Rattrapage : tout ce qui n'a pas encore été lancé
--
-- Ce fichier regroupe trois morceaux :
--   A. l'administrateur change identifiants et mots de passe
--   B. les clients revendeurs, les ventes et les factures
--   C. le suivi de présence continu et l'itinéraire
--
-- Il est relançable autant de fois qu'on veut : si un morceau est déjà
-- installé, il est simplement remis à jour.
--
-- ⚠ Si Supabase dit « must be owner of table users », répondez
--   « Run without RLS ».
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;


-- =====================================================================
-- A. IDENTIFIANTS ET MOTS DE PASSE
-- =====================================================================

create or replace function public.admin_changer_mot_de_passe(
  p_profil uuid, p_nouveau text)
returns text language plpgsql security definer
set search_path = public, extensions as $$
declare cible public.profils%rowtype;
begin
  if public.mon_role() <> 'admin' then
    raise exception 'Reserve a l administrateur';
  end if;
  if p_nouveau is null or length(p_nouveau) < 6 then
    raise exception 'Le mot de passe doit faire au moins 6 caracteres';
  end if;
  select * into cible from public.profils where id = p_profil;
  if cible.id is null then raise exception 'Utilisateur introuvable'; end if;

  update auth.users
     set encrypted_password = extensions.crypt(
           p_nouveau, extensions.gen_salt('bf')),
         updated_at = now()
   where id = p_profil;

  return cible.login;
end $$;

create or replace function public.admin_changer_identifiant(
  p_profil uuid, p_nouveau text)
returns text language plpgsql security definer
set search_path = public, extensions as $$
declare propre text; mail text;
begin
  if public.mon_role() <> 'admin' then
    raise exception 'Reserve a l administrateur';
  end if;
  propre := lower(btrim(coalesce(p_nouveau, '')));
  if length(propre) < 3 then
    raise exception 'L identifiant doit faire au moins 3 caracteres';
  end if;
  if propre !~ '^[a-z0-9._-]+$' then
    raise exception 'Lettres, chiffres, point, tiret et souligne uniquement';
  end if;
  if exists (select 1 from public.profils
              where login = propre and id <> p_profil) then
    raise exception 'Identifiant deja pris : %', propre;
  end if;
  if not exists (select 1 from public.profils where id = p_profil) then
    raise exception 'Utilisateur introuvable';
  end if;

  mail := propre || '@idiamaa.com';
  update public.profils set login = propre where id = p_profil;
  update auth.users set email = mail, updated_at = now() where id = p_profil;
  -- Sans cette ligne, Supabase garde l'ancienne adresse dans sa fiche
  -- d'identite et la connexion echoue sans dire pourquoi.
  update auth.identities
     set identity_data = jsonb_set(coalesce(identity_data, '{}'::jsonb),
                                   '{email}', to_jsonb(mail)),
         updated_at = now()
   where user_id = p_profil and provider = 'email';
  return propre;
end $$;

revoke all on function public.admin_changer_mot_de_passe(uuid, text)
  from public, anon;
revoke all on function public.admin_changer_identifiant(uuid, text)
  from public, anon;
grant execute on function public.admin_changer_mot_de_passe(uuid, text)
  to authenticated;
grant execute on function public.admin_changer_identifiant(uuid, text)
  to authenticated;


-- =====================================================================
-- B. CLIENTS REVENDEURS, VENTES ET FACTURES
-- =====================================================================

create sequence if not exists public.facture_numero start 1;

create table if not exists public.clients (
  id           uuid primary key default gen_random_uuid(),
  ferme_id     uuid not null references public.fermes(id) on delete cascade,
  cree_par     uuid references public.profils(id) on delete set null,
  nom          text not null,
  type         text not null default 'revendeur',
  telephone    text default '',
  telephone2   text default '',
  adresse      text default '',
  note         text default '',
  actif        boolean not null default true,
  cree_le      timestamptz not null default now()
);
create index if not exists idx_clients_ferme on public.clients(ferme_id, nom);

create table if not exists public.ventes (
  id           uuid primary key default gen_random_uuid(),
  client_id    uuid not null references public.clients(id) on delete cascade,
  ferme_id     uuid not null references public.fermes(id) on delete cascade,
  auteur_id    uuid not null references public.profils(id) on delete cascade,
  role_auteur  text not null default 'gerant',
  recette_id   uuid references public.recettes(id) on delete set null,
  reference    text not null default
                 ('FA-' || to_char(now(), 'YYYY') || '-'
                  || lpad(nextval('public.facture_numero')::text, 5, '0')),
  date         date not null default current_date,
  nb_alveoles  integer not null default 0,
  prix_alveole bigint not null default 0,
  montant      bigint not null default 0,
  paye         boolean not null default true,
  note         text default '',
  cree_le      timestamptz not null default now()
);
create index if not exists idx_ventes_client on public.ventes(client_id, date desc);
create index if not exists idx_ventes_ferme  on public.ventes(ferme_id, date desc);


-- =====================================================================
-- C. PRESENCE CONTINUE ET ITINERAIRE
-- =====================================================================

alter table public.pointages
  add column if not exists derniere_verif    timestamptz,
  add column if not exists derniere_distance integer,
  add column if not exists motif_sortie      text,
  add column if not exists suivi_jusqua      timestamptz;

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


-- =====================================================================
-- PROTECTION DES QUATRE NOUVELLES TABLES
-- =====================================================================

alter table public.clients      enable row level security;
alter table public.ventes       enable row level security;
alter table public.sorties_zone enable row level security;
alter table public.trajets      enable row level security;

do $$
declare r record;
begin
  for r in select tablename, policyname from pg_policies
            where schemaname = 'public'
              and tablename in ('clients','ventes','sorties_zone','trajets')
  loop
    execute format('drop policy %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;

create policy cli_lecture on public.clients for select to authenticated
  using (public.ma_ferme_est(ferme_id));
create policy cli_creation on public.clients for insert to authenticated
  with check (public.est_actif() and public.ma_ferme_est(ferme_id)
              and public.mon_role() in ('admin','gerant'));
create policy cli_maj on public.clients for update to authenticated
  using (public.est_actif() and public.ma_ferme_est(ferme_id)
         and public.mon_role() in ('admin','gerant'))
  with check (public.ma_ferme_est(ferme_id));
create policy cli_suppr on public.clients for delete to authenticated
  using (public.ma_ferme_est(ferme_id)
         and public.mon_role() in ('admin','gerant'));

create policy ven_lecture on public.ventes for select to authenticated
  using (public.ma_ferme_est(ferme_id));
create policy ven_creation on public.ventes for insert to authenticated
  with check (public.est_actif() and auteur_id = auth.uid()
              and public.ma_ferme_est(ferme_id)
              and public.mon_role() in ('admin','gerant'));
create policy ven_maj on public.ventes for update to authenticated
  using (public.est_actif() and public.ma_ferme_est(ferme_id)
         and public.mon_role() in ('admin','gerant'))
  with check (public.ma_ferme_est(ferme_id));
create policy ven_suppr on public.ventes for delete to authenticated
  using (public.ma_ferme_est(ferme_id)
         and public.mon_role() in ('admin','gerant'));

-- L'interesse voit son propre trajet : c'est la moindre des choses,
-- et ca evite qu'il decouvre le suivi par hasard.
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

revoke all on public.clients      from anon;
revoke all on public.ventes       from anon;
revoke all on public.sorties_zone from anon;
revoke all on public.trajets      from anon;
grant select, insert, update, delete on public.clients to authenticated;
grant select, insert, update, delete on public.ventes  to authenticated;
grant select, update, delete on public.sorties_zone to authenticated;
grant select, delete         on public.trajets      to authenticated;
grant usage, select on sequence public.facture_numero to authenticated;


-- =====================================================================
-- LES FONCTIONS
-- =====================================================================

-- Une vente cree AUSSI la recette qui va avec : impossible d'avoir une
-- facture sans l'argent correspondant dans les comptes de la ferme.
create or replace function public.enregistrer_vente(
  p_client uuid, p_date date, p_nb_alveoles integer,
  p_prix_alveole bigint, p_paye boolean, p_note text default '')
returns table (reference text, montant bigint)
language plpgsql security definer set search_path = public as $$
declare moi public.profils%rowtype; cli public.clients%rowtype;
        total bigint; id_rec uuid; ref text;
begin
  select * into moi from public.profils where id = auth.uid();
  if moi.id is null then raise exception 'Connexion requise'; end if;
  if moi.suspendu then raise exception 'Compte suspendu'; end if;
  if moi.role not in ('admin','gerant') then
    raise exception 'Seuls le gerant et l administrateur enregistrent une vente';
  end if;

  select * into cli from public.clients where id = p_client;
  if cli.id is null then raise exception 'Client introuvable'; end if;
  if moi.role <> 'admin' and cli.ferme_id <> moi.ferme_id then
    raise exception 'Ce client n est pas celui de votre ferme';
  end if;
  if p_nb_alveoles is null or p_nb_alveoles <= 0 then
    raise exception 'Indiquez le nombre d alveoles';
  end if;
  if p_prix_alveole is null or p_prix_alveole <= 0 then
    raise exception 'Indiquez le prix de l alveole';
  end if;

  total := p_nb_alveoles::bigint * p_prix_alveole;

  insert into public.recettes
    (ferme_id, auteur_id, role_auteur, produit, quantite,
     prix_unitaire, montant, description, date, statut)
  values (cli.ferme_id, moi.id, moi.role, 'Oeufs (alveole)', p_nb_alveoles,
     p_prix_alveole, total, 'Vente a ' || cli.nom, p_date,
     case moi.role when 'admin' then 'valide' else 'attente_admin' end)
  returning id into id_rec;

  insert into public.ventes
    (client_id, ferme_id, auteur_id, role_auteur, recette_id,
     date, nb_alveoles, prix_alveole, montant, paye, note)
  values (p_client, cli.ferme_id, moi.id, moi.role, id_rec,
     p_date, p_nb_alveoles, p_prix_alveole, total,
     coalesce(p_paye, true), coalesce(p_note, ''))
  returning ventes.reference into ref;

  reference := ref; montant := total;
  return next;
end $$;

-- Supprimer une vente retire aussi la recette : sinon l'argent resterait
-- dans les comptes sans facture en face.
create or replace function public.supprimer_vente(p_vente uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v public.ventes%rowtype;
begin
  select * into v from public.ventes where id = p_vente;
  if v.id is null then return; end if;
  if public.mon_role() not in ('admin','gerant')
     or not public.ma_ferme_est(v.ferme_id) then
    raise exception 'Non autorise';
  end if;
  delete from public.ventes where id = p_vente;
  if v.recette_id is not null then
    delete from public.recettes where id = v.recette_id;
  end if;
end $$;

-- Le telephone dit ou il est. Trois issues : present, sorti de la zone
-- (mise hors ligne immediate), ou simple point de trajet apres la sortie.
create or replace function public.confirmer_presence(
  p_latitude double precision, p_longitude double precision)
returns table (en_ligne boolean, distance integer, motif text)
language plpgsql security definer set search_path = public as $$
declare moi public.profils%rowtype; f public.fermes%rowtype;
        p public.pointages%rowtype; dist double precision;
begin
  select * into moi from public.profils where id = auth.uid();
  if moi.id is null then raise exception 'Connexion requise'; end if;

  select * into p from public.pointages
   where profil_id = moi.id and statut = 'en_cours'
   order by debut desc limit 1;

  if p.id is null then
    -- Plus de pointage ouvert : on n'accepte des points que si la
    -- fenetre de suivi ouverte a la sortie n'est pas encore refermee.
    select * into p from public.pointages
     where profil_id = moi.id and suivi_jusqua is not null
       and suivi_jusqua > now()
     order by debut desc limit 1;
    if p.id is null then
      en_ligne := false; distance := null; motif := 'Aucun suivi en cours';
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
    en_ligne := true; distance := null; motif := 'Pas de controle';
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
     set derniere_verif = now(), derniere_distance = round(dist)::int
   where id = p.id;

  insert into public.trajets
    (pointage_id, profil_id, ferme_id, latitude, longitude, distance)
  values (p.id, moi.id, p.ferme_id, p_latitude, p_longitude, round(dist)::int);

  if dist > f.rayon_metres then
    update public.pointages
       set fin = now(),
           duree = greatest(0, extract(epoch from (now() - debut))::int),
           statut = 'termine',
           lat_sortie = p_latitude, lon_sortie = p_longitude,
           sortie_auto = true,
           motif_sortie = 'Sorti de la zone (' || round(dist)::text || ' m)',
           -- La fenetre de suivi : 2 heures, pas une de plus.
           suivi_jusqua = now() + interval '2 hours'
     where id = p.id;
    insert into public.sorties_zone
      (pointage_id, profil_id, ferme_id, latitude, longitude, distance)
    values (p.id, moi.id, p.ferme_id, p_latitude, p_longitude,
            round(dist)::int);
    en_ligne := false; distance := round(dist)::int;
    motif := 'Vous avez quitte la ferme (' || round(dist)::text || ' m)';
    return next; return;
  end if;

  en_ligne := true; distance := round(dist)::int; motif := 'Present';
  return next;
end $$;

-- Le telephone se tait : application tuee, GPS coupe, batterie vide.
-- Au bout de 30 minutes sans position, on ferme. Le silence n'est plus
-- une echappatoire.
create or replace function public.fermer_pointages_silencieux(
  p_minutes integer default 30)
returns integer language plpgsql security definer
set search_path = public as $$
declare n integer;
begin
  with concernes as (
    select p.id, coalesce(p.derniere_verif, p.debut) as dernier_signe
      from public.pointages p
      join public.profils pr on pr.id = p.profil_id
      join public.fermes  f  on f.id  = p.ferme_id
     where p.statut = 'en_cours' and pr.role = 'fermier'
       and f.latitude is not null
       and coalesce(p.derniere_verif, p.debut)
             < now() - make_interval(mins => p_minutes)
  )
  update public.pointages p
     set fin = c.dernier_signe,
         duree = greatest(0,
           extract(epoch from (c.dernier_signe - p.debut))::int),
         statut = 'termine', sortie_auto = true,
         motif_sortie = 'Plus de nouvelles du telephone depuis '
                        || p_minutes::text || ' minutes'
    from concernes c where p.id = c.id;
  get diagnostics n = row_count;
  return n;
end $$;

revoke all on function public.enregistrer_vente(uuid, date, integer, bigint, boolean, text)
  from public, anon;
revoke all on function public.supprimer_vente(uuid) from public, anon;
revoke all on function public.confirmer_presence(double precision, double precision)
  from public, anon;
revoke all on function public.fermer_pointages_silencieux(integer)
  from public, anon;
grant execute on function public.enregistrer_vente(uuid, date, integer, bigint, boolean, text)
  to authenticated;
grant execute on function public.supprimer_vente(uuid) to authenticated;
grant execute on function public.confirmer_presence(double precision, double precision)
  to authenticated;
grant execute on function public.fermer_pointages_silencieux(integer)
  to authenticated;


-- =====================================================================
-- CONTROLE — l'etat complet de votre base
-- =====================================================================
select 'A. Changer un mot de passe' as verification,
  case when exists (select 1 from pg_proc p join pg_namespace n
      on n.oid = p.pronamespace
    where n.nspname='public' and p.proname='admin_changer_mot_de_passe')
  then 'OK' else 'ECHEC' end as resultat
union all
select 'A. Changer un identifiant',
  case when exists (select 1 from pg_proc p join pg_namespace n
      on n.oid = p.pronamespace
    where n.nspname='public' and p.proname='admin_changer_identifiant')
  then 'OK' else 'ECHEC' end
union all
select 'B. Table clients',
  case when exists (select 1 from information_schema.tables
    where table_schema='public' and table_name='clients') then 'OK' else 'ECHEC' end
union all
select 'B. Table ventes',
  case when exists (select 1 from information_schema.tables
    where table_schema='public' and table_name='ventes') then 'OK' else 'ECHEC' end
union all
select 'B. Numerotation des factures',
  case when exists (select 1 from pg_class
    where relkind='S' and relname='facture_numero') then 'OK' else 'ECHEC' end
union all
select 'B. Vente liee a une recette',
  case when exists (select 1 from pg_proc p join pg_namespace n
      on n.oid = p.pronamespace
    where n.nspname='public' and p.proname='enregistrer_vente')
  then 'OK' else 'ECHEC' end
union all
select 'C. Journal des sorties',
  case when exists (select 1 from information_schema.tables
    where table_schema='public' and table_name='sorties_zone')
  then 'OK' else 'ECHEC' end
union all
select 'C. Table des trajets',
  case when exists (select 1 from information_schema.tables
    where table_schema='public' and table_name='trajets')
  then 'OK' else 'ECHEC' end
union all
select 'C. Fenetre de suivi limitee a 2 h',
  case when exists (select 1 from information_schema.columns
    where table_schema='public' and table_name='pointages'
      and column_name='suivi_jusqua') then 'OK' else 'ECHEC' end
union all
select 'C. Fermeture des pointages muets',
  case when exists (select 1 from pg_proc p join pg_namespace n
      on n.oid = p.pronamespace
    where n.nspname='public' and p.proname='fermer_pointages_silencieux')
  then 'OK' else 'ECHEC' end
union all
select 'Les 4 nouvelles tables protegees',
  case when (select count(*) from pg_tables where schemaname='public'
    and rowsecurity=true
    and tablename in ('clients','ventes','sorties_zone','trajets')) = 4
  then 'OK' else 'ECHEC' end
union all
select 'Aucune porte pour les visiteurs',
  case when not exists (select 1 from information_schema.role_table_grants
    where table_schema='public' and grantee='anon'
      and table_name in ('clients','ventes','sorties_zone','trajets'))
  then 'OK' else 'ECHEC' end
union all
select 'Personne ne peut ecrire un faux trajet',
  case when not exists (select 1 from pg_policies
    where schemaname='public' and tablename='trajets' and cmd='INSERT')
  then 'OK' else 'ECHEC' end
union all
select '--- TOTAL DES TABLES DE VOTRE BASE ---',
  (select count(*)::text from information_schema.tables
    where table_schema='public' and table_type='BASE TABLE') || ' tables';
