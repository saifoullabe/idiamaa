-- =====================================================================
-- IDIAMA AGRO — 12. Sécurité et création des comptes
-- À lancer après 11. Relançable sans risque, autant de fois qu'on veut.
--
-- ⚠ Si l'éditeur SQL affiche « Potential issue detected » ou
--   « must be owner of table users », répondez « Run without RLS ».
--   Le message vient du bouton de l'éditeur, pas de ce fichier.
--
-- ⚠ Ce fichier va AVEC la nouvelle version de l'application (1.2.0).
--   Lancez-le, puis installez l'APK. Entre les deux, ne créez pas de
--   nouveau compte depuis l'ancienne application.
--
-- ⚠ Ne relancez plus les fichiers 01 et 03 après celui-ci : ils
--   remettraient les anciennes règles que ce fichier corrige.
--
-- Ce fichier répare :
--   A. La serrure qui laissait passer un compte sans fiche.
--   B. Les trois fonctions d'administration, avec une double garde.
--   C. La création d'un compte sans e-mail — la cause de
--      « création réussie, connexion impossible ».
--   D. Le déblocage des comptes déjà créés.
--   E. Le pointage, qui ne s'écrit plus à la main.
--   F. La liste des fermes, qui n'est plus lisible par tous.
--   G. Les photos et rapports, que seul l'admin peut effacer.
--   H. Le coffre à fichiers, où rien ne peut plus être remplacé.
--
-- LE TABLEAU DU BAS : les lignes qui commencent par A, B, C, D, E, F,
-- G ou H doivent TOUTES afficher OK. Les lignes qui commencent par
-- INFO ne sont pas des contrôles : elles vous renseignent, elles ne
-- disent ni OK ni ÉCHEC, et elles ne signalent aucun problème.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- =====================================================================
-- A. LA SERRURE — mon_role() ne répond plus « rien »
--
-- mon_role() lisait le rôle dans la fiche. Un compte connecté SANS
-- fiche (employé supprimé, création interrompue, inconnu inscrit par
-- Internet) n'a pas de fiche : la fonction répondait NULL. Or en SQL,
-- « NULL n'est pas admin » ne vaut ni vrai ni faux : les tests
-- « si le rôle n'est pas admin, refuser » ne refusaient donc rien.
-- Elle répond maintenant 'aucun', qui n'est ni admin, ni gérant, ni
-- fermier. Les quatre fonctions trouées sont réparées d'un coup.
-- =====================================================================
create or replace function public.mon_role()
returns text
language sql
stable
security definer
set search_path = public
as $$ select coalesce((select role from public.profils where id = auth.uid()), 'aucun') $$;

create or replace function public.ma_ferme_est(cible uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$ select coalesce(public.mon_role() = 'admin' or cible = public.ma_ferme(), false) $$;

revoke all on function public.mon_role() from public, anon;
revoke all on function public.ma_ferme_est(uuid) from public, anon;
grant execute on function public.mon_role() to authenticated;
grant execute on function public.ma_ferme_est(uuid) to authenticated;

-- =====================================================================
-- B. LES TROIS FONCTIONS D'ADMINISTRATION
-- Même signature qu'avant (sinon deux versions coexisteraient et la
-- base ne saurait plus laquelle appeler). Deux gardes au lieu d'une.
-- =====================================================================
create or replace function public.admin_changer_mot_de_passe(
  p_profil uuid, p_nouveau text)
returns text language plpgsql security definer
set search_path = public, extensions as $$
declare cible public.profils%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Connexion requise';
  end if;
  if coalesce(public.mon_role(), 'aucun') <> 'admin' then
    raise exception 'Reserve a l administrateur';
  end if;
  if p_nouveau is null or length(p_nouveau) < 6 then
    raise exception 'Le mot de passe doit faire au moins 6 caracteres';
  end if;
  select * into cible from public.profils where id = p_profil;
  if cible.id is null then raise exception 'Utilisateur introuvable'; end if;
  update auth.users
     set encrypted_password = extensions.crypt(p_nouveau, extensions.gen_salt('bf', 10)),
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
  if auth.uid() is null then
    raise exception 'Connexion requise';
  end if;
  if coalesce(public.mon_role(), 'aucun') <> 'admin' then
    raise exception 'Reserve a l administrateur';
  end if;
  propre := lower(btrim(coalesce(p_nouveau, '')));
  if length(propre) < 3 then
    raise exception 'L identifiant doit faire au moins 3 caracteres';
  end if;
  if propre !~ '^[a-z0-9._-]+$' then
    raise exception 'Lettres, chiffres, point, tiret et souligne uniquement';
  end if;
  if exists (select 1 from public.profils where login = propre and id <> p_profil) then
    raise exception 'Identifiant deja pris : %', propre;
  end if;
  if not exists (select 1 from public.profils where id = p_profil) then
    raise exception 'Utilisateur introuvable';
  end if;
  mail := propre || '@idiamaa.com';
  if exists (select 1 from auth.users where email = mail and id <> p_profil) then
    raise exception 'Identifiant deja pris : %', propre;
  end if;
  update public.profils set login = propre where id = p_profil;
  update auth.users set email = mail, updated_at = now() where id = p_profil;
  update auth.identities
     set identity_data = jsonb_set(coalesce(identity_data, '{}'::jsonb),
                                   '{email}', to_jsonb(mail)),
         updated_at = now()
   where user_id = p_profil and provider = 'email';
  return propre;
end $$;

create or replace function public.nouveau_numero_acces()
returns text language plpgsql security definer
set search_path = public as $$
declare n text; essais integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Connexion requise';
  end if;
  if coalesce(public.mon_role(), 'aucun') <> 'admin' then
    raise exception 'Reserve a l administrateur';
  end if;
  loop
    -- Entre 10000000 et 99999999 : toujours huit chiffres, jamais de
    -- zéro en tête qu'un fermier oublierait de taper.
    n := (floor(random() * 90000000) + 10000000)::bigint::text;
    exit when not exists (select 1 from public.profils where login = n)
          and not exists (select 1 from auth.users where email = n || '@idiamaa.com');
    essais := essais + 1;
    if essais > 50 then
      raise exception 'Impossible de tirer un numero libre';
    end if;
  end loop;
  return n;
end $$;

-- =====================================================================
-- C. CRÉER ET SUPPRIMER UN COMPTE, SANS E-MAIL
--
-- Jusqu'ici l'application créait le compte par la porte d'inscription
-- publique. Supabase envoyait alors un courriel de confirmation à une
-- adresse qui n'existe pas (12345678@idiamaa.com) : le compte restait
-- verrouillé pour toujours. Ici, la base crée le compte elle-même,
-- déjà confirmé, et la fiche dans le même mouvement : soit les deux
-- existent, soit aucun des deux.
-- =====================================================================
create or replace function public.admin_creer_utilisateur(
  p_login        text,
  p_mot_de_passe text,
  p_role         text,
  p_ferme        uuid default null,
  p_champs       jsonb default '{}'::jsonb)
returns uuid language plpgsql security definer
set search_path = public, extensions as $$
declare
  propre text;
  mail   text;
  uid    uuid;
  champs jsonb := coalesce(p_champs, '{}'::jsonb);
begin
  if auth.uid() is null then
    raise exception 'Connexion requise';
  end if;
  if coalesce(public.mon_role(), 'aucun') <> 'admin' then
    raise exception 'Reserve a l administrateur';
  end if;

  propre := lower(btrim(coalesce(p_login, '')));
  if length(propre) < 3 then
    raise exception 'L identifiant doit faire au moins 3 caracteres';
  end if;
  if propre !~ '^[a-z0-9._-]+$' then
    raise exception 'Lettres, chiffres, point, tiret et souligne uniquement';
  end if;
  if p_mot_de_passe is null or length(p_mot_de_passe) < 6 then
    raise exception 'Le mot de passe doit faire au moins 6 caracteres';
  end if;
  if p_role is null or p_role not in ('admin', 'gerant', 'fermier') then
    raise exception 'Choisissez un role : admin, gerant ou fermier';
  end if;
  if p_role <> 'admin' and p_ferme is null then
    raise exception 'Choisissez une ferme';
  end if;
  if p_ferme is not null and not exists (select 1 from public.fermes where id = p_ferme) then
    raise exception 'Ferme introuvable';
  end if;

  mail := propre || '@idiamaa.com';
  if exists (select 1 from public.profils where login = propre)
     or exists (select 1 from auth.users where email = mail) then
    raise exception 'L identifiant % est deja utilise', propre;
  end if;

  uid := gen_random_uuid();

  -- Les huit colonnes de jetons valent chaîne vide et non NULL : sinon
  -- la connexion échoue plus tard par une erreur 500 que l'application
  -- traduirait à tort en « mot de passe incorrect ».
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data,
    confirmation_token, recovery_token,
    email_change, email_change_token_new, email_change_token_current,
    phone_change, phone_change_token, reauthentication_token
  ) values (
    '00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated',
    mail, extensions.crypt(p_mot_de_passe, extensions.gen_salt('bf', 10)),
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    '', '', '', '', '', '', '', ''
  );

  insert into auth.identities (
    id, user_id, provider_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at
  ) values (
    gen_random_uuid(), uid, uid::text,
    jsonb_build_object('sub', uid::text, 'email', mail, 'email_verified', true),
    'email', now(), now(), now()
  );

  insert into public.profils (
    id, login, nom, prenom, role, ferme_id, tel, tel2,
    date_naissance, lieu_naissance, pere, mere, quartier, commune,
    date_embauche, salaire, notes, photo_url, piece_url, contrat_url
  ) values (
    uid, propre,
    coalesce(champs->>'nom', ''), coalesce(champs->>'prenom', ''),
    p_role, p_ferme,
    coalesce(champs->>'tel', ''), coalesce(champs->>'tel2', ''),
    nullif(champs->>'date_naissance', '')::date,
    coalesce(champs->>'lieu_naissance', ''),
    coalesce(champs->>'pere', ''), coalesce(champs->>'mere', ''),
    coalesce(champs->>'quartier', ''), coalesce(champs->>'commune', ''),
    nullif(champs->>'date_embauche', '')::date,
    coalesce(nullif(champs->>'salaire', '')::bigint, 0),
    coalesce(champs->>'notes', ''),
    nullif(champs->>'photo_url', ''),
    nullif(champs->>'piece_url', ''),
    nullif(champs->>'contrat_url', '')
  );

  return uid;
end $$;

-- Retirer un employé doit lui couper l'accès. Jusqu'ici seule la fiche
-- était effacée : le compte de connexion survivait, sans fiche — donc
-- avec le rôle « aucun », celui qui passait à travers les serrures.
create or replace function public.admin_supprimer_utilisateur(p_profil uuid)
returns void language plpgsql security definer
set search_path = public as $$
begin
  if auth.uid() is null then
    raise exception 'Connexion requise';
  end if;
  if coalesce(public.mon_role(), 'aucun') <> 'admin' then
    raise exception 'Reserve a l administrateur';
  end if;
  if p_profil = auth.uid() then
    raise exception 'Vous ne pouvez pas supprimer votre propre compte';
  end if;
  if not exists (select 1 from public.profils where id = p_profil) then
    raise exception 'Utilisateur introuvable';
  end if;
  if (select role from public.profils where id = p_profil) = 'admin'
     and not exists (select 1 from public.profils
                      where role = 'admin' and not suspendu and id <> p_profil) then
    raise exception 'Il doit rester au moins un administrateur';
  end if;

  -- Effacer le compte emporte, par cascade, TOUT ce que la personne a
  -- saisi. Tant qu elle a une ligne dans les comptes, on refuse : il
  -- faut la suspendre, ce qui coupe son acces sans rien perdre.
  if exists (select 1 from public.recettes    where auteur_id = p_profil)
     or exists (select 1 from public.depenses    where auteur_id = p_profil)
     or exists (select 1 from public.productions where auteur_id = p_profil)
     or exists (select 1 from public.depots      where auteur_id = p_profil) then
    raise exception 'Cette personne a des saisies dans les comptes : suspendez son compte au lieu de l effacer';
  end if;

  -- Couper les sessions : le telephone ne pourra plus renouveler son
  -- jeton. Le jeton deja en memoire reste valable au plus une heure,
  -- mais sans fiche la personne ne peut plus rien lire ni ecrire.
  if to_regclass('auth.sessions') is not null then
    execute 'delete from auth.sessions where user_id = $1' using p_profil;
  end if;
  -- La fiche part avec, par la cle etrangere on delete cascade.
  delete from auth.users where id = p_profil;
end $$;

revoke all on function public.admin_changer_mot_de_passe(uuid, text) from public, anon;
revoke all on function public.admin_changer_identifiant(uuid, text) from public, anon;
revoke all on function public.nouveau_numero_acces() from public, anon;
revoke all on function public.admin_creer_utilisateur(text, text, text, uuid, jsonb) from public, anon;
revoke all on function public.admin_supprimer_utilisateur(uuid) from public, anon;
grant execute on function public.admin_changer_mot_de_passe(uuid, text) to authenticated;
grant execute on function public.admin_changer_identifiant(uuid, text) to authenticated;
grant execute on function public.nouveau_numero_acces() to authenticated;
grant execute on function public.admin_creer_utilisateur(text, text, text, uuid, jsonb) to authenticated;
grant execute on function public.admin_supprimer_utilisateur(uuid) to authenticated;

-- =====================================================================
-- D. DÉBLOQUER LES COMPTES DÉJÀ CRÉÉS
-- On remet aussi les huit colonnes de jetons à chaîne vide : un seul
-- NULL suffit à faire échouer la connexion par une erreur 500 que
-- l'application traduit à tort en « mot de passe incorrect ».
-- =====================================================================
update auth.users u
   set email_confirmed_at         = coalesce(u.email_confirmed_at, now()),
       updated_at                 = now(),
       confirmation_token         = coalesce(u.confirmation_token, ''),
       recovery_token             = coalesce(u.recovery_token, ''),
       email_change               = coalesce(u.email_change, ''),
       email_change_token_new     = coalesce(u.email_change_token_new, ''),
       email_change_token_current = coalesce(u.email_change_token_current, ''),
       phone_change               = coalesce(u.phone_change, ''),
       phone_change_token         = coalesce(u.phone_change_token, ''),
       reauthentication_token     = coalesce(u.reauthentication_token, '')
 where exists (select 1 from public.profils p where p.id = u.id)
   and (u.email_confirmed_at is null
        or u.confirmation_token is null or u.recovery_token is null
        or u.email_change is null or u.email_change_token_new is null
        or u.email_change_token_current is null or u.phone_change is null
        or u.phone_change_token is null or u.reauthentication_token is null);

-- =====================================================================
-- E. LE POINTAGE NE S'ÉCRIT PLUS À LA MAIN
-- Un fermier pouvait écrire lui-même sa ligne de présence, sans être à
-- la ferme, et modifier ensuite ses heures. Seules les fonctions de la
-- base écrivent désormais : elles vérifient la distance, et elles
-- continuent de fonctionner car elles s'exécutent avec les droits du
-- propriétaire des tables.
-- =====================================================================
do $$
declare r record;
begin
  for r in select policyname from pg_policies
            where schemaname = 'public' and tablename = 'pointages'
              and cmd in ('INSERT', 'UPDATE', 'ALL')
  loop
    execute format('drop policy %I on public.pointages', r.policyname);
  end loop;
end $$;
revoke insert, update on public.pointages from authenticated, anon, public;

-- Cette fonction ferme les pointages des AUTRES. Elle était ouverte à
-- tout compte connecté : un fermier pouvait mettre hors ligne tous ses
-- collègues d'un coup. Elle est maintenant réservée, et le délai ne
-- peut plus être ramené à zéro.
create or replace function public.fermer_pointages_silencieux(
  p_minutes integer default 30)
returns integer language plpgsql security definer
set search_path = public as $$
declare n integer; m integer := greatest(coalesce(p_minutes, 30), 5);
begin
  if coalesce(public.mon_role(), 'aucun') not in ('admin', 'gerant') then
    raise exception 'Reserve au gerant et a l administrateur';
  end if;
  with concernes as (
    select p.id, coalesce(p.derniere_verif, p.debut) as dernier_signe
      from public.pointages p
      join public.profils pr on pr.id = p.profil_id
      join public.fermes  f  on f.id  = p.ferme_id
     where p.statut = 'en_cours' and pr.role = 'fermier'
       and f.latitude is not null
       and coalesce(p.derniere_verif, p.debut) < now() - make_interval(mins => m)
  )
  update public.pointages p
     set fin = c.dernier_signe,
         duree = greatest(0, extract(epoch from (c.dernier_signe - p.debut))::int),
         statut = 'termine', sortie_auto = true,
         motif_sortie = 'Plus de nouvelles du telephone depuis ' || m::text || ' minutes'
    from concernes c where p.id = c.id;
  get diagnostics n = row_count;
  return n;
end $$;

revoke all on function public.fermer_pointages_silencieux(integer) from public, anon;
grant execute on function public.fermer_pointages_silencieux(integer) to authenticated;

-- =====================================================================
-- F. CHACUN NE VOIT QUE SA FERME
-- La liste des fermes — adresses, coordonnées GPS, prix, gérant — était
-- lisible par n'importe quel compte connecté. L'administrateur voit
-- toujours tout ; les autres ne voient que la leur.
-- =====================================================================
do $$
declare r record;
begin
  for r in select policyname from pg_policies
            where schemaname = 'public' and tablename = 'fermes'
              and cmd in ('SELECT', 'ALL')
  loop
    execute format('drop policy %I on public.fermes', r.policyname);
  end loop;
end $$;
create policy fermes_lecture on public.fermes for select to authenticated
  using (public.ma_ferme_est(id));

-- =====================================================================
-- G. RIEN NE SE PERD — PHOTOS, RAPPORTS, SIGNALEMENTS
-- Tout gérant pouvait effacer définitivement une photo ou un rapport
-- envoyé à l'administrateur, y compris ceux d'une autre ferme. Seul
-- l'administrateur peut désormais effacer, et seulement chez lui.
-- La nouvelle version de l'application retire le bouton Supprimer aux
-- autres, pour que personne ne croie avoir effacé sans l'avoir fait.
-- =====================================================================
do $$
declare r record;
begin
  for r in select tablename, policyname from pg_policies
            where schemaname = 'public'
              and tablename in ('photos', 'rapports', 'signalements')
              and cmd in ('DELETE', 'UPDATE', 'ALL')
  loop
    execute format('drop policy %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;

create policy photos_maj on public.photos for update to authenticated
  using (public.est_actif() and public.ma_ferme_est(ferme_id)
         and (auteur_id = auth.uid() or public.mon_role() in ('admin', 'gerant')))
  with check (public.ma_ferme_est(ferme_id));
create policy photos_suppr on public.photos for delete to authenticated
  using (public.mon_role() = 'admin' and public.ma_ferme_est(ferme_id));

create policy rap_maj on public.rapports for update to authenticated
  using (public.est_actif() and public.ma_ferme_est(ferme_id)
         and (auteur_id = auth.uid() or public.mon_role() in ('admin', 'gerant')))
  with check (public.ma_ferme_est(ferme_id));
create policy rap_suppr on public.rapports for delete to authenticated
  using (public.mon_role() = 'admin' and public.ma_ferme_est(ferme_id));

-- Le gérant doit pouvoir clôturer un signalement : la modification lui
-- reste ouverte, sur sa ferme seulement.
create policy sig_maj on public.signalements for update to authenticated
  using (public.est_actif() and public.ma_ferme_est(ferme_id))
  with check (public.ma_ferme_est(ferme_id));
create policy sig_suppr on public.signalements for delete to authenticated
  using (public.mon_role() = 'admin' and public.ma_ferme_est(ferme_id));

-- =====================================================================
-- H. LE COFFRE À FICHIERS
-- Un fichier déjà envoyé ne peut plus être remplacé ni déplacé, et seul
-- l'administrateur peut en effacer un. Le coffre reste lisible par lien
-- pour l'instant : le fermer demande que l'application sache demander
-- des liens signés, ce qui viendra avec la version suivante.
-- =====================================================================
do $$
declare r record;
begin
  for r in select policyname from pg_policies
            where schemaname = 'storage' and tablename = 'objects'
              and cmd in ('UPDATE', 'ALL')
  loop
    execute format('drop policy %I on storage.objects', r.policyname);
  end loop;
end $$;
drop policy if exists idiama_docs_depot on storage.objects;
drop policy if exists idiama_docs_suppr on storage.objects;

create policy idiama_docs_depot on storage.objects for insert to authenticated
  with check (bucket_id = 'documents' and public.est_actif());
create policy idiama_docs_suppr on storage.objects for delete to authenticated
  using (bucket_id = 'documents' and public.mon_role() = 'admin');

-- Taille acceptée. La liste des types reste ouverte : l'application
-- envoie aussi des .mkv, des .avi et des fichiers de type inconnu, que
-- refuser ferait perdre la vidéo du fermier sans explication.
-- Si la base refuse ce réglage, le reste du fichier passe quand même.
do $$
begin
  update storage.buckets
     set file_size_limit = 62914560,
         allowed_mime_types = null
   where id = 'documents';
exception when others then
  raise notice 'Limites du coffre non appliquees : a regler dans Storage > documents';
end $$;

-- =====================================================================
-- CONTRÔLE
-- Pour atteindre la serrure réparée, il faut se faire passer pour un
-- compte connecté SANS fiche : c'est exactement la situation du trou.
-- Puis on crée un vrai compte, on vérifie qu'il pourrait se connecter,
-- et on l'efface — la preuve par le geste, pas par le catalogue.
-- =====================================================================
create or replace function public.idiama_controle_12()
returns table (verification text, resultat text)
language plpgsql security definer
set search_path = public, extensions as $$
declare
  faux        uuid := '00000000-0000-0000-0000-000000000000';
  msg         text;
  n           integer;
  adm         uuid;
  essai       uuid;
  essai_login text := 'ctrl' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISS');
  essai_passe text;
begin
  essai_passe := 'controle-' || essai_login;

  -- On se fait passer pour un compte connecté sans fiche. Le troisième
  -- argument (true) limite l'effet à cette seule requête.
  perform set_config('request.jwt.claim.sub', faux::text, true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', faux::text, 'role', 'authenticated')::text, true);

  verification := 'A. Un compte connecte sans fiche vaut « aucun »';
  resultat := case
    when auth.uid() is null then 'ECHEC — le test n a pas pu simuler un compte'
    when public.mon_role() = 'aucun' then 'OK'
    else 'ECHEC — il vaut ' || coalesce(public.mon_role(), '(rien)') end;
  return next;

  begin
    perform public.admin_changer_mot_de_passe(faux, 'essai_de_controle');
    resultat := 'ECHEC — la fonction a laisse passer';
  exception when others then
    msg := sqlerrm;
    resultat := case when msg = 'Reserve a l administrateur'
                then 'OK' else 'ECHEC — ' || msg end;
  end;
  verification := 'B. Changer un mot de passe est refuse a un inconnu';
  return next;

  begin
    perform public.admin_changer_identifiant(faux, 'essaidecontrole');
    resultat := 'ECHEC — la fonction a laisse passer';
  exception when others then
    msg := sqlerrm;
    resultat := case when msg = 'Reserve a l administrateur'
                then 'OK' else 'ECHEC — ' || msg end;
  end;
  verification := 'B. Changer un identifiant est refuse a un inconnu';
  return next;

  begin
    perform public.nouveau_numero_acces();
    resultat := 'ECHEC — la fonction a laisse passer';
  exception when others then
    msg := sqlerrm;
    resultat := case when msg = 'Reserve a l administrateur'
                then 'OK' else 'ECHEC — ' || msg end;
  end;
  verification := 'B. Tirer un numero d acces est refuse a un inconnu';
  return next;

  begin
    perform public.admin_creer_utilisateur('controle12', 'essai_de_controle', 'fermier', null);
    resultat := 'ECHEC — la fonction a laisse passer';
  exception when others then
    msg := sqlerrm;
    resultat := case when msg = 'Reserve a l administrateur'
                then 'OK' else 'ECHEC — ' || msg end;
  end;
  verification := 'C. Creer un compte est refuse a un inconnu';
  return next;

  begin
    perform public.admin_supprimer_utilisateur(faux);
    resultat := 'ECHEC — la fonction a laisse passer';
  exception when others then
    msg := sqlerrm;
    resultat := case when msg = 'Reserve a l administrateur'
                then 'OK' else 'ECHEC — ' || msg end;
  end;
  verification := 'C. Supprimer un compte est refuse a un inconnu';
  return next;

  verification := 'C. Le controle n a cree aucun compte';
  resultat := case when not exists (select 1 from public.profils where login = 'controle12')
                    and not exists (select 1 from auth.users where email = 'controle12@idiamaa.com')
              then 'OK' else 'ECHEC — supprimez le compte controle12' end;
  return next;

  -- On redevient l'administrateur pour la preuve par le geste.
  select id into adm from public.profils
   where role = 'admin' and not suspendu order by cree_le limit 1;
  begin
    if adm is null then
      resultat := 'ECHEC — aucun administrateur en base';
    else
      perform set_config('request.jwt.claim.sub', adm::text, true);
      perform set_config('request.jwt.claims',
        json_build_object('sub', adm::text, 'role', 'authenticated')::text, true);
      essai := public.admin_creer_utilisateur(essai_login, essai_passe, 'admin', null);
      if exists (
          select 1 from auth.users u
            join auth.identities i on i.user_id = u.id and i.provider = 'email'
            join public.profils p on p.id = u.id
           where u.id = essai
             and u.email_confirmed_at is not null
             and u.aud = 'authenticated' and u.role = 'authenticated'
             and u.encrypted_password = extensions.crypt(essai_passe, u.encrypted_password)
             and i.identity_data->>'email' = u.email)
      then resultat := 'OK — il se connecterait';
      else resultat := 'ECHEC — le compte cree est incomplet';
      end if;
      perform public.admin_supprimer_utilisateur(essai);
    end if;
  exception when others then
    resultat := 'ECHEC — ' || sqlerrm;
  end;
  verification := 'C. Un vrai compte cree pourrait se connecter';
  return next;

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);

  verification := 'C. La creation est utilisable par l application';
  select count(*) into n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
   where s.nspname = 'public' and p.proname = 'admin_creer_utilisateur';
  resultat := case
    when n <> 1 then 'ECHEC — ' || n::text || ' versions, l appel serait ambigu'
    when to_regprocedure('public.admin_creer_utilisateur(text,text,text,uuid,jsonb)') is null
      then 'ECHEC — la signature attendue par l application n existe pas'
    when not has_function_privilege('authenticated',
      'public.admin_creer_utilisateur(text,text,text,uuid,jsonb)', 'execute')
      then 'ECHEC — l application n a pas le droit de l appeler'
    else 'OK' end;
  return next;

  select count(*) into n
    from auth.users u join public.profils p on p.id = u.id
   where u.email_confirmed_at is null
      or u.confirmation_token is null or u.recovery_token is null
      or u.email_change is null or u.email_change_token_new is null
      or u.email_change_token_current is null or u.phone_change is null
      or u.phone_change_token is null or u.reauthentication_token is null;
  verification := 'D. Comptes avec fiche encore bloques';
  resultat := case when n = 0 then 'OK — aucun' else 'ECHEC — ' || n::text end;
  return next;

  if exists (select 1 from information_schema.columns
              where table_schema = 'auth' and table_name = 'users'
                and column_name = 'deleted_at') then
    execute 'select count(*) from auth.users u left join public.profils p on p.id = u.id
              where p.id is null and u.deleted_at is null' into n;
  else
    select count(*) into n from auth.users u
      left join public.profils p on p.id = u.id where p.id is null;
  end if;
  verification := 'INFO. Comptes de connexion sans fiche';
  resultat := case when n = 0 then 'aucun'
              else n::text || ' — souvent d anciens employes. Ils peuvent encore se '
                   || 'connecter mais ne voient plus aucune donnee. A supprimer depuis '
                   || 'Authentication > Users.' end;
  return next;

  verification := 'E. Le fermier ne peut plus ecrire son pointage';
  resultat := case when not has_table_privilege('authenticated', 'public.pointages', 'insert')
                    and not has_table_privilege('authenticated', 'public.pointages', 'update')
              then 'OK' else 'ECHEC' end;
  return next;

  verification := 'E. Le pointage par l application fonctionne toujours';
  resultat := case when (
      select bool_and(p.prosecdef
             and has_function_privilege('authenticated', p.oid, 'execute'))
        from pg_proc p join pg_namespace s on s.oid = p.pronamespace
       where s.nspname = 'public'
         and p.proname in ('pointer_arrivee', 'pointer_sortie', 'confirmer_presence'))
    then 'OK' else 'ECHEC — plus personne ne peut pointer, ne quittez pas cette page' end;
  return next;

  select count(*) into n from pg_policies
   where schemaname = 'public' and tablename = 'fermes' and cmd in ('SELECT', 'ALL')
     and (qual is null or qual not like '%ma_ferme_est%');
  verification := 'F. Les fermes ne sont plus lisibles par tous';
  resultat := case
    when n > 0 then 'ECHEC — ' || n::text || ' regle(s) laissent tout lire'
    when not exists (select 1 from pg_policies where schemaname = 'public'
                      and tablename = 'fermes' and cmd = 'SELECT'
                      and qual like '%ma_ferme_est%')
      then 'ECHEC — la nouvelle regle de lecture est absente'
    else 'OK' end;
  return next;

  -- On ne compte pas les règles « admin » : on cherche celles qui
  -- laisseraient effacer quelqu'un d'autre. Il ne doit y en avoir aucune.
  select count(*) into n from pg_policies
   where schemaname = 'public' and tablename in ('photos', 'rapports', 'signalements')
     and cmd in ('DELETE', 'ALL')
     and (qual is null or qual like '%gerant%' or qual not like '%admin%');
  verification := 'G. Seul l administrateur efface photos et rapports';
  resultat := case when n = 0 then 'OK'
              else 'ECHEC — ' || n::text || ' regle(s) laissent effacer un non-admin' end;
  return next;

  verification := 'H. Un fichier envoye ne peut plus etre remplace';
  resultat := case when not exists (
      select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
        and cmd in ('UPDATE', 'ALL'))
    then 'OK' else 'ECHEC — une regle de modification existe encore' end;
  return next;

  verification := 'INFO. Taille maximale des fichiers';
  resultat := case when (select file_size_limit from storage.buckets
                          where id = 'documents') = 62914560
              then '60 Mo'
              else 'non posee — a regler dans Storage > documents > Settings' end;
  return next;

  verification := 'INFO. Le coffre est-il encore lisible par lien';
  resultat := case when exists (select 1 from storage.buckets
                                 where id = 'documents' and public)
              then 'oui — sera ferme a la version suivante'
              else 'non — coffre prive' end;
  return next;

  select count(*) into n from information_schema.tables
   where table_schema = 'public' and table_type = 'BASE TABLE';
  verification := 'INFO. Tables de votre base';
  resultat := n::text || ' tables';
  return next;
end $$;

revoke all on function public.idiama_controle_12() from public, anon, authenticated;

-- PostgREST garde en mémoire la liste des fonctions : on lui dit de la
-- relire, sinon le premier appel répondrait « fonction introuvable ».
notify pgrst, 'reload schema';

select * from public.idiama_controle_12();
