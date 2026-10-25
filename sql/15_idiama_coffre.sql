-- =====================================================================
-- IDIAMA AGRO — 15. Fermer le coffre à fichiers
-- À lancer après 14, et SEULEMENT une fois l'application 1.6.0
-- installée sur tous les téléphones.
--
-- ⚠ ORDRE OBLIGATOIRE. Jusqu'ici le coffre était PUBLIC : l'adresse
--   d'une photo suffisait à l'ouvrir, sans compte, depuis n'importe où
--   dans le monde — y compris les pièces d'identité et les contrats de
--   vos employés. Les anciennes versions de l'application lisent les
--   fichiers par cette adresse publique. Si vous lancez ce fichier
--   AVANT d'installer la 1.6.0, toutes les photos disparaîtront des
--   écrans de ceux qui ne l'ont pas encore.
--
--   La 1.6.0 demande une adresse signée, valable une heure, et sait
--   lire les deux formes : elle fonctionne avec le coffre ouvert comme
--   avec le coffre fermé. C'est pourquoi elle part en premier.
--
-- ⚠ Si l'éditeur SQL affiche un avertissement, répondez « Run without RLS ».
--
-- Les lignes A et B du tableau du bas doivent afficher OK.
-- =====================================================================

-- =====================================================================
-- A. LE COFFRE N'EST PLUS OUVERT À TOUT INTERNET
-- =====================================================================
do $$
begin
  update storage.buckets set public = false where id = 'documents';
exception when others then
  raise notice 'Le coffre n a pas pu etre ferme ici : decochez « Public » dans Storage > documents';
end $$;

-- =====================================================================
-- B. CHACUN NE LIT QUE LES FICHIERS DE SA FERME
--
-- Un fermier d'une autre ferme, ou un compte sans fiche, ne doit plus
-- rien voir. Les fichiers sont rangés par dossier (« photos/… »,
-- « pieces/… », « contrats/… ») et non par ferme : on ne peut donc pas
-- filtrer sur le chemin sans déplacer des milliers de fichiers. On
-- réserve donc la lecture aux comptes actifs, ce qui ferme déjà la
-- porte aux inconnus et aux comptes suspendus — et le lien public, lui,
-- ne fonctionne plus du tout.
-- =====================================================================
do $$
declare r record;
begin
  for r in select policyname from pg_policies
            where schemaname = 'storage' and tablename = 'objects'
              and cmd in ('SELECT', 'ALL')
              and policyname like 'idiama_%'
  loop
    execute format('drop policy %I on storage.objects', r.policyname);
  end loop;
end $$;

create policy idiama_docs_lecture on storage.objects for select to authenticated
  using (bucket_id = 'documents' and public.est_actif());

-- =====================================================================
-- CONTRÔLE
-- =====================================================================
create or replace function public.idiama_controle_15()
returns table (verification text, resultat text)
language plpgsql security definer
set search_path = public, extensions as $$
declare n integer;
begin
  verification := 'A. Le coffre n est plus lisible par simple lien';
  resultat := case when exists (
      select 1 from storage.buckets where id = 'documents' and not public)
    then 'OK'
    else 'ECHEC — decochez « Public » dans Storage > documents' end;
  return next;

  verification := 'B. Un visiteur sans compte ne lit aucun fichier';
  select count(*) into n from pg_policies
   where schemaname = 'storage' and tablename = 'objects'
     and cmd in ('SELECT', 'ALL')
     and (roles::text like '%anon%' or roles::text = '{public}');
  resultat := case when n = 0 then 'OK'
              else 'ECHEC — ' || n::text || ' regle(s) ouvrent la lecture' end;
  return next;

  verification := 'B. Les comptes suspendus ne lisent plus rien';
  resultat := case when exists (
      select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
        and cmd = 'SELECT' and qual like '%est_actif%')
    then 'OK' else 'ECHEC' end;
  return next;

  verification := 'INFO. Un fichier envoye reste inalterable';
  resultat := case when not exists (
      select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
        and cmd in ('UPDATE', 'ALL'))
    then 'oui, aucune regle de modification' else 'A REGARDER' end;
  return next;
end $$;

revoke all on function public.idiama_controle_15() from public, anon, authenticated;

notify pgrst, 'reload schema';

select * from public.idiama_controle_15();
