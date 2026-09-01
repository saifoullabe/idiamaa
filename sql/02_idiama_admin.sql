-- =====================================================================
-- IDIAMA AGRO — Création du compte administrateur
-- À lancer APRÈS 01_idiama_base.sql
--
-- ⚠ Dans le SQL Editor de Supabase, si un message dit
--   « must be owner of table users », répondez « Run without RLS ».
--
-- Ce fichier NE CONTIENT AUCUN MOT DE PASSE.
-- Il en fabrique un au hasard et vous l'affiche UNE SEULE FOIS,
-- dans le tableau de résultat, en bas de l'écran.
--
-- 👉 NOTEZ-LE AVANT DE FERMER LA PAGE. Il n'est stocké nulle part
--    en clair : ni ici, ni dans la base, ni dans l'application.
--    Si vous le perdez, relancez simplement ce fichier : il en
--    fabriquera un nouveau et remplacera l'ancien.
-- =====================================================================

create extension if not exists pgcrypto;

create or replace function public.idiama_creer_admin()
returns table (element text, valeur text)
language plpgsql
security definer
set search_path = public
as $$
declare
  uid    uuid;
  mail   text := 'admin@idiamaa.com';
  motdep text;
begin
  -- Mot de passe tiré au hasard : majuscules, minuscules et chiffres.
  motdep := 'Idiama'
            || lpad(floor(random() * 10000)::int::text, 4, '0')
            || '-'
            || substr(md5(random()::text || clock_timestamp()::text), 1, 6);

  select id into uid from auth.users where email = mail;

  if uid is null then
    uid := gen_random_uuid();
    -- Les huit colonnes de jetons doivent valoir '' et non NULL,
    -- sinon la connexion échoue avec une erreur 500 déguisée en
    -- « mot de passe incorrect ».
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, created_at, updated_at,
      raw_app_meta_data, raw_user_meta_data,
      confirmation_token, recovery_token,
      email_change, email_change_token_new, email_change_token_current,
      phone_change, phone_change_token, reauthentication_token
    ) values (
      '00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated',
      mail, crypt(motdep, gen_salt('bf')),
      now(), now(), now(),
      '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
      '', '', '', '', '', '', '', ''
    );

    insert into auth.identities (
      id, user_id, provider_id, identity_data, provider,
      last_sign_in_at, created_at, updated_at
    ) values (
      gen_random_uuid(), uid, uid::text,
      json_build_object('sub', uid::text, 'email', mail)::jsonb,
      'email', now(), now(), now()
    );
  else
    update auth.users
       set encrypted_password = crypt(motdep, gen_salt('bf')),
           email_confirmed_at = coalesce(email_confirmed_at, now()),
           confirmation_token = coalesce(confirmation_token, ''),
           recovery_token     = coalesce(recovery_token, ''),
           email_change       = coalesce(email_change, '')
     where id = uid;
  end if;

  insert into public.profils (id, login, nom, prenom, role, ferme_id)
  values (uid, 'admin', 'IDIAMA', 'Administrateur', 'admin', null)
  on conflict (id) do update set role = 'admin', suspendu = false;

  -- ── Ce que l'écran doit afficher ──
  element := '👤  Identifiant';           valeur := 'admin';   return next;
  element := '🔑  Mot de passe';          valeur := motdep;    return next;
  element := '⚠️  À faire maintenant';    valeur := 'Notez ce mot de passe, il ne sera plus jamais affiché.'; return next;

  element := '✅  Compte prêt';
  valeur := case when exists (
      select 1 from auth.users u
        join public.profils p on p.id = u.id
       where u.email = mail
         and u.email_confirmed_at is not null
         and p.role = 'admin')
    then 'oui' else 'NON — quelque chose a échoué' end;
  return next;

  element := '✅  Jetons corrects';
  valeur := case when exists (
      select 1 from auth.users
       where email = mail
         and confirmation_token is not null
         and recovery_token is not null
         and email_change is not null)
    then 'oui' else 'NON — la connexion échouera' end;
  return next;
end $$;

revoke all on function public.idiama_creer_admin() from public, anon, authenticated;

-- ── Lancement ──
select * from public.idiama_creer_admin();

-- La fonction ne sert qu'une fois : on l'efface pour que personne
-- ne puisse s'en servir plus tard pour réécrire le mot de passe admin.
drop function public.idiama_creer_admin();
