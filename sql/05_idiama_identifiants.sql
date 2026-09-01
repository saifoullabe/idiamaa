-- =====================================================================
-- IDIAMA AGRO — L'administrateur peut changer identifiants et mots de passe
-- À lancer après 01. Relançable sans risque.
--
-- ⚠ Si Supabase dit « must be owner of table users », répondez
--   « Run without RLS ».
--
-- Pourquoi passer par la base plutôt que par l'application :
-- changer le mot de passe d'un AUTRE compte exige la clé de service de
-- Supabase. Mettre cette clé dans l'application reviendrait à la donner
-- à tous ceux qui l'installent — elle ouvre tout, sans aucune règle.
-- Ces deux fonctions font le travail à l'intérieur de la base, et
-- vérifient elles-mêmes que celui qui appelle est bien administrateur.
-- =====================================================================

-- ── Changer le MOT DE PASSE de n'importe quel compte ──────────────────
create or replace function public.admin_changer_mot_de_passe(
  p_profil  uuid,
  p_nouveau text
)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare cible public.profils%rowtype;
begin
  -- La seule barrière qui compte : le rôle de l'appelant, lu dans la
  -- base, jamais dans ce que l'application prétend être.
  if public.mon_role() <> 'admin' then
    raise exception 'Réservé à l''administrateur';
  end if;

  if p_nouveau is null or length(p_nouveau) < 6 then
    raise exception 'Le mot de passe doit faire au moins 6 caractères';
  end if;

  select * into cible from public.profils where id = p_profil;
  if cible.id is null then
    raise exception 'Utilisateur introuvable';
  end if;

  update auth.users
     set encrypted_password = extensions.crypt(
           p_nouveau, extensions.gen_salt('bf')),
         updated_at = now()
   where id = p_profil;

  return cible.login;
end $$;

-- ── Changer l'IDENTIFIANT de n'importe quel compte ────────────────────
-- L'identifiant sert aussi d'adresse de connexion (identifiant@idiamaa.com) :
-- il faut donc le changer aux deux endroits, sinon la personne ne peut
-- plus entrer du tout.
create or replace function public.admin_changer_identifiant(
  p_profil  uuid,
  p_nouveau text
)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  propre text;
  mail   text;
begin
  if public.mon_role() <> 'admin' then
    raise exception 'Réservé à l''administrateur';
  end if;

  propre := lower(btrim(coalesce(p_nouveau, '')));

  if length(propre) < 3 then
    raise exception 'L''identifiant doit faire au moins 3 caractères';
  end if;
  if propre !~ '^[a-z0-9._-]+$' then
    raise exception 'Lettres, chiffres, point, tiret et souligné uniquement — ni espace ni accent';
  end if;
  if exists (select 1 from public.profils
              where login = propre and id <> p_profil) then
    raise exception 'L''identifiant « % » est déjà pris', propre;
  end if;
  if not exists (select 1 from public.profils where id = p_profil) then
    raise exception 'Utilisateur introuvable';
  end if;

  mail := propre || '@idiamaa.com';

  update public.profils set login = propre where id = p_profil;

  update auth.users
     set email = mail,
         updated_at = now()
   where id = p_profil;

  -- Sans cette ligne, Supabase garde l'ancienne adresse dans sa fiche
  -- d'identité et la connexion échoue sans dire pourquoi.
  update auth.identities
     set identity_data = jsonb_set(
           coalesce(identity_data, '{}'::jsonb), '{email}', to_jsonb(mail)),
         updated_at = now()
   where user_id = p_profil and provider = 'email';

  return propre;
end $$;

-- Personne d'autre que les gens connectés ne peut même les appeler ;
-- et à l'intérieur, seul un administrateur passe.
revoke all on function public.admin_changer_mot_de_passe(uuid, text)
  from public, anon;
revoke all on function public.admin_changer_identifiant(uuid, text)
  from public, anon;
grant execute on function public.admin_changer_mot_de_passe(uuid, text)
  to authenticated;
grant execute on function public.admin_changer_identifiant(uuid, text)
  to authenticated;

-- ── Contrôle ─────────────────────────────────────────────────────────
select 'Fonction mot de passe' as verification,
  case when exists (select 1 from pg_proc p join pg_namespace n
      on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'admin_changer_mot_de_passe')
  then 'creee  OK' else 'ABSENTE  ECHEC' end as resultat
union all
select 'Fonction identifiant',
  case when exists (select 1 from pg_proc p join pg_namespace n
      on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'admin_changer_identifiant')
  then 'creee  OK' else 'ABSENTE  ECHEC' end
union all
select 'Elles s''executent avec les droits du proprietaire',
  case when (select count(*) from pg_proc p join pg_namespace n
      on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef = true
      and p.proname in ('admin_changer_mot_de_passe','admin_changer_identifiant')) = 2
  then 'oui  OK' else 'NON  ECHEC' end
union all
select 'Fermees aux visiteurs non connectes',
  case when not exists (
    select 1 from information_schema.role_routine_grants
     where routine_schema = 'public' and grantee = 'anon'
       and routine_name in ('admin_changer_mot_de_passe','admin_changer_identifiant'))
  then 'oui  OK' else 'NON  ECHEC' end;
