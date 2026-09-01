-- =====================================================================
-- IDIAMA AGRO — Clients revendeurs et factures
-- À lancer après 01. Relançable sans risque.
--
-- Le gérant tient la fiche de ses revendeurs ; l'administrateur voit
-- tout. Chaque achat note la date, le nombre d'alvéoles, le prix de
-- l'alvéole et le total — et porte un numéro de facture unique.
--
-- Une vente à un client crée AUSSI une recette dans la ferme, avec le
-- parcours de validation habituel : sinon il faudrait saisir la même
-- vente deux fois, et les deux finiraient par diverger.
-- =====================================================================

-- Numérotation des factures : une seule suite pour toute l'entreprise,
-- pour qu'aucun numéro ne soit jamais donné deux fois.
create sequence if not exists public.facture_numero start 1;

create table if not exists public.clients (
  id           uuid primary key default gen_random_uuid(),
  ferme_id     uuid not null references public.fermes(id) on delete cascade,
  cree_par     uuid references public.profils(id) on delete set null,
  nom          text not null,
  type         text not null default 'revendeur', -- revendeur | particulier | marche | restaurant
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

-- ── Protection ───────────────────────────────────────────────────────
alter table public.clients enable row level security;
alter table public.ventes  enable row level security;

do $$
declare r record;
begin
  for r in select tablename, policyname from pg_policies
            where schemaname = 'public' and tablename in ('clients','ventes')
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

revoke all on public.clients from anon;
revoke all on public.ventes  from anon;
grant select, insert, update, delete on public.clients to authenticated;
grant select, insert, update, delete on public.ventes  to authenticated;
grant usage, select on sequence public.facture_numero to authenticated;

-- ── Enregistrer une vente ET la recette qui va avec, d'un seul geste ──
-- Les deux réussissent ou aucune : impossible d'avoir une facture sans
-- l'argent correspondant dans les comptes de la ferme.
create or replace function public.enregistrer_vente(
  p_client       uuid,
  p_date         date,
  p_nb_alveoles  integer,
  p_prix_alveole bigint,
  p_paye         boolean,
  p_note         text default ''
)
returns table (reference text, montant bigint)
language plpgsql
security definer
set search_path = public
as $$
declare
  moi      public.profils%rowtype;
  cli      public.clients%rowtype;
  total    bigint;
  id_rec   uuid;
  ref      text;
begin
  select * into moi from public.profils where id = auth.uid();
  if moi.id is null then raise exception 'Connexion requise'; end if;
  if moi.suspendu then raise exception 'Compte suspendu'; end if;
  if moi.role not in ('admin','gerant') then
    raise exception 'Seuls le gérant et l''administrateur enregistrent une vente';
  end if;

  select * into cli from public.clients where id = p_client;
  if cli.id is null then raise exception 'Client introuvable'; end if;
  if moi.role <> 'admin' and cli.ferme_id <> moi.ferme_id then
    raise exception 'Ce client n''est pas celui de votre ferme';
  end if;

  if p_nb_alveoles is null or p_nb_alveoles <= 0 then
    raise exception 'Indiquez le nombre d''alvéoles';
  end if;
  if p_prix_alveole is null or p_prix_alveole <= 0 then
    raise exception 'Indiquez le prix de l''alvéole';
  end if;

  total := p_nb_alveoles::bigint * p_prix_alveole;

  insert into public.recettes
    (ferme_id, auteur_id, role_auteur, produit, quantite,
     prix_unitaire, montant, description, date, statut)
  values
    (cli.ferme_id, moi.id, moi.role, 'Œufs (alvéole)', p_nb_alveoles,
     p_prix_alveole, total, 'Vente à ' || cli.nom, p_date,
     case moi.role when 'admin' then 'valide' else 'attente_admin' end)
  returning id into id_rec;

  insert into public.ventes
    (client_id, ferme_id, auteur_id, role_auteur, recette_id,
     date, nb_alveoles, prix_alveole, montant, paye, note)
  values
    (p_client, cli.ferme_id, moi.id, moi.role, id_rec,
     p_date, p_nb_alveoles, p_prix_alveole, total, coalesce(p_paye, true),
     coalesce(p_note, ''))
  returning ventes.reference into ref;

  reference := ref;
  montant := total;
  return next;
end $$;

revoke all on function public.enregistrer_vente(uuid, date, integer, bigint, boolean, text)
  from public, anon;
grant execute on function public.enregistrer_vente(uuid, date, integer, bigint, boolean, text)
  to authenticated;

-- Supprimer une vente doit aussi retirer la recette : sinon l'argent
-- resterait dans les comptes sans facture en face.
create or replace function public.supprimer_vente(p_vente uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v public.ventes%rowtype;
begin
  select * into v from public.ventes where id = p_vente;
  if v.id is null then return; end if;
  if public.mon_role() not in ('admin','gerant')
     or not public.ma_ferme_est(v.ferme_id) then
    raise exception 'Non autorisé';
  end if;
  delete from public.ventes where id = p_vente;
  if v.recette_id is not null then
    delete from public.recettes where id = v.recette_id;
  end if;
end $$;

revoke all on function public.supprimer_vente(uuid) from public, anon;
grant execute on function public.supprimer_vente(uuid) to authenticated;

-- ── Contrôle ─────────────────────────────────────────────────────────
select 'Table clients' as verification,
  case when exists (select 1 from information_schema.tables
    where table_schema='public' and table_name='clients')
  then 'creee  OK' else 'ABSENTE  ECHEC' end as resultat
union all
select 'Table ventes',
  case when exists (select 1 from information_schema.tables
    where table_schema='public' and table_name='ventes')
  then 'creee  OK' else 'ABSENTE  ECHEC' end
union all
select 'Numerotation des factures',
  case when exists (select 1 from pg_class
    where relkind='S' and relname='facture_numero')
  then 'prete  OK' else 'ABSENTE  ECHEC' end
union all
select 'Les deux tables protegees',
  case when (select count(*) from pg_tables where schemaname='public'
    and rowsecurity=true and tablename in ('clients','ventes')) = 2
  then 'oui  OK' else 'NON  ECHEC' end
union all
select 'Vente liee a une recette',
  case when exists (select 1 from pg_proc p join pg_namespace n
      on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='enregistrer_vente')
  then 'oui  OK' else 'NON  ECHEC' end
union all
select 'Regles d''acces (8 attendues)',
  (select count(*)::text from pg_policies where schemaname='public'
    and tablename in ('clients','ventes'))
  || case when (select count(*) from pg_policies where schemaname='public'
       and tablename in ('clients','ventes')) = 8
     then '  OK' else '  ECHEC' end;
