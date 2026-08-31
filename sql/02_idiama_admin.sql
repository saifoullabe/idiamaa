-- =====================================================================
-- IDIAMA AGRO — Création du compte administrateur
-- À lancer APRÈS 01_idiama_base.sql
--
-- ⚠ Dans le SQL Editor de Supabase, si un message dit
--   « must be owner of table users », répondez « Run without RLS ».
--
-- Identifiant de connexion dans l'application : admin
-- Mot de passe                                : Admin2024!
-- (changeable ensuite depuis « Mon compte » dans l'application)
-- =====================================================================

do $$
declare
  uid    uuid;
  mail   text := 'admin@idiamaa.com';
  motdep text := 'Admin2024!';
begin
  select id into uid from auth.users where email = mail;

  if uid is null then
    uid := gen_random_uuid();
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
      id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at
    ) values (
      gen_random_uuid(), uid, uid::text,
      json_build_object('sub', uid::text, 'email', mail)::jsonb,
      'email', now(), now(), now()
    );
  else
    update auth.users
       set encrypted_password = crypt(motdep, gen_salt('bf')),
           email_confirmed_at = coalesce(email_confirmed_at, now())
     where id = uid;
  end if;

  insert into public.profils (id, login, nom, prenom, role, ferme_id)
  values (uid, 'admin', 'IDIAMA', 'Administrateur', 'admin', null)
  on conflict (id) do update set role = 'admin', suspendu = false;
end $$;

-- ── Contrôle ──
select
  'Compte admin' as verification,
  case when exists (
    select 1 from auth.users u
      join public.profils p on p.id = u.id
     where u.email = 'admin@idiamaa.com'
       and u.email_confirmed_at is not null
       and p.role = 'admin'
  ) then 'prêt — identifiant « admin », mot de passe « Admin2024! »  ✅'
    else 'ÉCHEC  ❌' end as resultat
union all
select
  'Jetons vides (sinon erreur 500 au login)',
  case when exists (
    select 1 from auth.users
     where email = 'admin@idiamaa.com'
       and confirmation_token is not null
       and recovery_token is not null
       and email_change is not null
  ) then 'corrects  ✅' else 'À CORRIGER  ❌' end;
