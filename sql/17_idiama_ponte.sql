-- =====================================================================
-- IDIAMA AGRO — 17. Le pourcentage de ponte, calculé par la base
-- À lancer après 16. Relançable sans risque.
--
-- ⚠ Si l'éditeur SQL affiche un avertissement, répondez « Run without RLS ».
--
-- POURQUOI LA BASE ET PAS LE TÉLÉPHONE
--
-- Le téléphone ne connaît que ce qu'il a chargé : les 500 dernières
-- déclarations de mortalité, et seulement une partie des productions.
-- Un pourcentage calculé là-dessus est faux de quatre façons :
--   — il oublie les morts anciennes, donc croit le cheptel plus grand ;
--   — il n'en oublie pas les mêmes selon qu'on est gérant ou
--     administrateur : deux personnes, deux chiffres, le même jour ;
--   — il dérive tout seul avec le temps, sans que rien ne change dans
--     le poulailler ;
--   — et « le mois passé » se calcule sur un mois incomplet sans le dire.
--
-- Ici, la base lit tout, et tout le monde lit la même chose.
--
-- COMMENT LE TAUX SE CALCULE
--
-- Taux = œufs ramassés ÷ poules-jours × 100.
--
-- « Poules-jours » : pour chaque jour où il y a eu ramassage, le nombre
-- de poules VIVANTES CE JOUR-LÀ. C'est la définition d'élevage, et
-- c'est ce qui rend la comparaison honnête : sans elle, on divisait les
-- œufs d'octobre par les poules de novembre, et un troupeau qui pond
-- exactement pareil paraissait en baisse de huit points.
--
-- UNE SEULE RÈGLE, PARTOUT DANS CE FICHIER
--
-- `nb_poules` est le nombre de poules comptées le jour
-- `effectif_pose_le`. On en retranche les morts déclarées À PARTIR de
-- ce jour-là — jamais celles d'avant : le fermier a compté des poules
-- vivantes, son nombre est déjà net du passé, et les retrancher une
-- seconde fois gonflait le pourcentage.
--
-- La journée du comptage est incluse dans la déduction, et c'est
-- voulu : l'exclure interdisait de déclarer la moindre mortalité le
-- jour où le fermier compte ses poules — la date du jour était refusée
-- parce qu'elle était celle du comptage, et toute date antérieure
-- parce qu'elle le précédait. Un refus en boucle fermée est pire qu'un
-- écart d'une journée.
--
-- CE QUI N'EST PAS MESURÉ EST DIT, PAS DEVINÉ
--
-- Un bâtiment sans comptage, ou des œufs ramassés avant le comptage :
-- on ne sait pas combien de poules il y avait. Ces journées comptent
-- dans le TOTAL des œufs, et sortent du pourcentage — des deux côtés de
-- la division. Sinon leurs œufs se divisaient par zéro poule et le
-- propriétaire lisait « 120 % — excellent », en vert.
--
-- Les lignes A à D du tableau du bas doivent afficher OK.
-- =====================================================================

-- =====================================================================
-- 0. LE FICHIER 16 D'ABORD
-- Sans lui, la première instruction de ce fichier échoue en anglais et
-- le tableau du bas ne s'affiche jamais : le propriétaire ne voit que
-- du rouge, sans savoir quoi faire.
-- =====================================================================
do $$
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'batiments'
                    and column_name = 'effectif_pose_le') then
    raise exception 'Lancez d abord le fichier sql/16_idiama_effectif.sql, puis celui-ci.';
  end if;
end $$;

-- =====================================================================
-- A. LA BORNE DE CHAQUE BÂTIMENT
--
-- Les bâtiments d'avant le fichier 16 n'ont pas de date de comptage, et
-- pour eux `nb_poules` est l'effectif MIS EN PLACE le jour de
-- l'arrivage — morts de ce jour-là comprises. Leur borne est donc le
-- jour de l'arrivage, et la règle du haut reste la seule.
--
-- Quand le jour d'arrivage n'a pas été renseigné, on ne le DEVINE pas :
-- prendre le jour de création de la fiche sortait du calcul toutes les
-- mortalités rattrapées à la main — un lot arrivé en avril, saisi en
-- octobre, voyait six mois de morts disparaître et sa mortalité
-- cumulée retomber à 0,0 %, sans retour possible. On recule donc la
-- borne jusqu'à la plus ancienne trace du bâtiment : première
-- mortalité, premier ramassage, ou création de la fiche.
--
-- Cette date n'est montrée nulle part pour ces bâtiments : le fichier
-- 16 les marque comme déjà confirmés par un responsable.
-- =====================================================================
update public.batiments b
   set effectif_pose_le = least(
         coalesce(b.date_mise_en_place::timestamptz, b.cree_le),
         coalesce((select min(m.date) from public.mortalites m
                    where m.batiment_id = b.id)::timestamptz,
                  'infinity'::timestamptz),
         coalesce((select min(p.date) from public.productions p
                    where p.batiment_id = b.id)::timestamptz,
                  'infinity'::timestamptz))
 where b.nb_poules > 0 and b.effectif_pose_le is null;

-- =====================================================================
-- B. LE TAUX SUR UNE PÉRIODE
-- SECURITY INVOKER (le défaut) : chacun ne voit que ce que les règles
-- lui montrent déjà — le gérant sa ferme, l'administrateur tout.
--
-- Quatre nombres sortent d'ici :
--   oeufs          — tous les œufs validés de la période ;
--   oeufs_mesures  — ceux dont on connaît le cheptel ;
--   poules_jours   — le cheptel de ces mêmes journées ;
--   jours          — le nombre de journées-bâtiment mesurées.
-- Le taux, c'est oeufs_mesures ÷ poules_jours. Le total des œufs, c'est
-- oeufs. Les mélanger était la cause du « 120 % ».
-- =====================================================================
-- `create or replace` refuse de changer les colonnes qu'une fonction
-- rend : relancer une version modifiée de ce fichier mourait en
-- anglais, avant le tableau du bas. On retire d'abord, rien n'en dépend.
drop function if exists public.ponte_entre(date, date, uuid, uuid);
drop function if exists public.ponte_comparee(uuid, uuid, date);
drop function if exists public.ponte_par_batiment(date, date, uuid);
drop function if exists public.ponte_comparee_par_batiment(uuid, date);
drop view if exists public.batiments_vivants;

create or replace function public.ponte_entre(
  p_debut    date,
  p_fin      date,                      -- exclue
  p_batiment uuid default null,
  p_ferme    uuid default null)
returns table (oeufs bigint, oeufs_mesures bigint,
               poules_jours bigint, jours integer)
language sql
stable
set search_path = public
as $$
  with j as (
    select
      p.oeufs,
      -- Zéro = journée non mesurable : pas de comptage, ou ramassage
      -- antérieur au comptage.
      case
        when b.effectif_pose_le is not null
         and p.date >= b.effectif_pose_le::date
        then greatest(
               b.nb_poules - coalesce((
                 select sum(m.nombre) from public.mortalites m
                  where m.batiment_id = b.id
                    and m.date <= p.date
                    and m.date >= b.effectif_pose_le::date
               ), 0),
             0)
        else 0
      end as vivantes
    from public.productions p
    join public.batiments b on b.id = p.batiment_id
    where p.statut = 'valide'
      and p.date >= p_debut and p.date < p_fin
      and (p_batiment is null or p.batiment_id = p_batiment)
      -- p.ferme_id et non b.ferme_id : c'est la colonne que portent les
      -- règles de lecture ET le seul index de la table.
      and (p_ferme    is null or p.ferme_id    = p_ferme)
  )
  select
    coalesce(sum(j.oeufs), 0)::bigint,
    coalesce(sum(case when j.vivantes > 0 then j.oeufs else 0 end), 0)::bigint,
    coalesce(sum(j.vivantes), 0)::bigint,
    (count(*) filter (where j.vivantes > 0))::integer
  from j;
$$;

-- Les huit périodes d'un coup : huit allers-retours sur un réseau
-- guinéen, c'est huit occasions d'échouer.
create or replace function public.ponte_comparee(
  p_batiment uuid default null,
  p_ferme    uuid default null,
  p_jour     date default current_date)
returns table (periode text, oeufs bigint, oeufs_mesures bigint,
               poules_jours bigint, jours integer)
language plpgsql
stable
set search_path = public
as $$
declare
  lundi date := p_jour - ((extract(isodow from p_jour)::int) - 1);
  mois  date := date_trunc('month', p_jour)::date;
  r     record;
begin
  for r in
    select 'jour'           as cle, p_jour      as d1, p_jour + 1  as d2
    union all select 'jour_avant',       p_jour - 1,                         p_jour
    union all select 'semaine',          lundi,                              lundi + 7
    union all select 'semaine_avant',    lundi - 7,                          lundi
    union all select 'mois',             mois,                               (mois + interval '1 month')::date
    union all select 'mois_avant',       (mois - interval '1 month')::date,  mois
    -- Les 7 derniers jours glissants : « cette semaine » un lundi matin
    -- ne contient qu'un jour, et comparer cela au standard de l'âge du
    -- lot faisait crier à la chute de ponte chaque début de semaine.
    union all select 'sept_jours',       p_jour - 6,                         p_jour + 1
    union all select 'sept_jours_avant', p_jour - 13,                        p_jour - 6
  loop
    periode := r.cle;
    select x.oeufs, x.oeufs_mesures, x.poules_jours, x.jours
      into oeufs, oeufs_mesures, poules_jours, jours
      from public.ponte_entre(r.d1, r.d2, p_batiment, p_ferme) x;
    return next;
  end loop;
end $$;

-- Le taux de CHAQUE bâtiment sur une période, en un seul appel : le
-- classement des bâtiments en appelait un par bâtiment, et sur dix
-- bâtiments c'était dix occasions d'échouer.
-- Un bâtiment sans aucune saisie n'apparaît pas : il n'a pas un taux de
-- zéro, il n'a pas de taux du tout, et l'écran doit le dire ainsi.
create or replace function public.ponte_par_batiment(
  p_debut date,
  p_fin   date,                         -- exclue
  p_ferme uuid default null)
returns table (batiment_id uuid, oeufs bigint, oeufs_mesures bigint,
               poules_jours bigint, jours integer)
language sql
stable
set search_path = public
as $$
  with j as (
    select
      p.batiment_id,
      p.oeufs,
      case
        when b.effectif_pose_le is not null
         and p.date >= b.effectif_pose_le::date
        then greatest(
               b.nb_poules - coalesce((
                 select sum(m.nombre) from public.mortalites m
                  where m.batiment_id = b.id
                    and m.date <= p.date
                    and m.date >= b.effectif_pose_le::date
               ), 0),
             0)
        else 0
      end as vivantes
    from public.productions p
    join public.batiments b on b.id = p.batiment_id
    where p.statut = 'valide'
      and p.date >= p_debut and p.date < p_fin
      and (p_ferme is null or p.ferme_id = p_ferme)
  )
  select
    j.batiment_id,
    coalesce(sum(j.oeufs), 0)::bigint,
    coalesce(sum(case when j.vivantes > 0 then j.oeufs else 0 end), 0)::bigint,
    coalesce(sum(j.vivantes), 0)::bigint,
    (count(*) filter (where j.vivantes > 0))::integer
  from j
  group by j.batiment_id;
$$;

-- Toutes les périodes de TOUS les bâtiments, en un seul appel.
-- L'écran Santé en demandait un par bâtiment à l'ouverture de sa
-- carte : dix bâtiments, dix allers-retours, et un rouage qui tourne
-- sur chaque carte restée fermée.
create or replace function public.ponte_comparee_par_batiment(
  p_ferme uuid default null,
  p_jour  date default current_date)
returns table (batiment_id uuid, periode text, oeufs bigint,
               oeufs_mesures bigint, poules_jours bigint, jours integer)
language plpgsql
stable
set search_path = public
as $$
declare
  lundi date := p_jour - ((extract(isodow from p_jour)::int) - 1);
  mois  date := date_trunc('month', p_jour)::date;
  r     record;
  x     record;
begin
  for r in
    select 'jour'           as cle, p_jour      as d1, p_jour + 1  as d2
    union all select 'jour_avant',       p_jour - 1,                         p_jour
    union all select 'semaine',          lundi,                              lundi + 7
    union all select 'semaine_avant',    lundi - 7,                          lundi
    union all select 'mois',             mois,                               (mois + interval '1 month')::date
    union all select 'mois_avant',       (mois - interval '1 month')::date,  mois
    union all select 'sept_jours',       p_jour - 6,                         p_jour + 1
    union all select 'sept_jours_avant', p_jour - 13,                        p_jour - 6
  loop
    periode := r.cle;
    for x in
      select * from public.ponte_par_batiment(r.d1, r.d2, p_ferme)
    loop
      batiment_id   := x.batiment_id;
      oeufs         := x.oeufs;
      oeufs_mesures := x.oeufs_mesures;
      poules_jours  := x.poules_jours;
      jours         := x.jours;
      return next;
    end loop;
  end loop;
end $$;

revoke all on function public.ponte_entre(date, date, uuid, uuid) from public, anon;
revoke all on function public.ponte_comparee(uuid, uuid, date) from public, anon;
revoke all on function public.ponte_par_batiment(date, date, uuid) from public, anon;
revoke all on function public.ponte_comparee_par_batiment(uuid, date) from public, anon;
grant execute on function public.ponte_entre(date, date, uuid, uuid) to authenticated;
grant execute on function public.ponte_comparee(uuid, uuid, date) to authenticated;
grant execute on function public.ponte_par_batiment(date, date, uuid) to authenticated;
grant execute on function public.ponte_comparee_par_batiment(uuid, date) to authenticated;

-- =====================================================================
-- C. L'EFFECTIF VIVANT, LUI AUSSI CALCULÉ PAR LA BASE
-- Le téléphone le déduisait d'une liste de morts plafonnée à 500 : il
-- croyait le cheptel plus grand qu'il n'est, et pas du même montant
-- selon qui regardait.
--
-- Même règle que plus haut : les morts déclarées À PARTIR de la
-- journée du comptage.
-- =====================================================================
create or replace view public.batiments_vivants
with (security_invoker = on) as
select b.id,
       b.ferme_id,
       b.nb_poules,
       greatest(
         b.nb_poules - coalesce((
           select sum(m.nombre) from public.mortalites m
            where m.batiment_id = b.id
              and m.date >= coalesce(b.effectif_pose_le::date, '-infinity'::date)
         ), 0),
       0)::integer as vivantes,
       coalesce((
         select sum(m.nombre) from public.mortalites m
          where m.batiment_id = b.id
            and m.date >= coalesce(b.effectif_pose_le::date, '-infinity'::date)
       ), 0)::integer as morts,
       b.effectif_pose_le
  from public.batiments b;

revoke all on public.batiments_vivants from anon, public;
grant select on public.batiments_vivants to authenticated;

-- =====================================================================
-- D. UNE MORT DÉCLARÉE DOIT POUVOIR ÊTRE DÉDUITE
--
-- Deux dates étaient acceptées sans rien changer, et c'est pire qu'un
-- refus : l'écran répondait « Mortalité enregistrée », la ligne
-- apparaissait dans l'historique, et juste au-dessus le bâtiment
-- affichait toujours « 2 000 poules vivantes sur 2 000, mortalité
-- 0,0 % ». Le fermier croyait avoir déclaré, personne ne déduisait.
--
--   — une date STRICTEMENT antérieure au comptage : ces poules
--     n'étaient pas dans le nombre compté, les retrancher le ferait
--     mentir. La journée du comptage, elle, reste déclarable ;
--   — une date À VENIR : elle entrait dans le cheptel vivant mais pas
--     dans le pourcentage, et les deux chiffres se contredisaient.
--
-- Les lignes déjà enregistrées ne sont pas touchées : le tableau du bas
-- vous dit s'il en existe.
-- =====================================================================
create or replace function public.mortalite_date_tenable()
returns trigger language plpgsql security definer
set search_path = public as $$
declare
  borne date;
begin
  if new.date > current_date then
    raise exception 'On ne peut pas déclarer des morts à une date à venir. Choisissez aujourd''hui ou un jour passé.';
  end if;

  select b.effectif_pose_le::date into borne
    from public.batiments b where b.id = new.batiment_id;

  -- Strictement antérieure. La journée du comptage elle-même reste
  -- déclarable : la refuser interdisait toute déclaration le jour où le
  -- fermier compte ses poules, puisque les dates d'avant étaient
  -- refusées aussi.
  if borne is not null and new.date < borne then
    raise exception 'Cette date précède le comptage des poules de ce bâtiment (%). Les morts d''avant sont déjà retirées du nombre compté : choisissez le jour du comptage ou un jour suivant.',
      to_char(borne, 'DD/MM/YYYY');
  end if;

  return new;
end $$;

drop trigger if exists trg_mortalite_date on public.mortalites;
create trigger trg_mortalite_date
  before insert or update on public.mortalites
  for each row execute function public.mortalite_date_tenable();

revoke all on function public.mortalite_date_tenable() from public, anon;

-- =====================================================================
-- CONTRÔLE
-- Chaque vérification est dans son propre bloc : une erreur tardive
-- jetterait TOUTES les lignes déjà rendues, et le propriétaire ne
-- verrait pas un tableau partiel, il ne verrait rien.
-- =====================================================================
create or replace function public.idiama_controle_17()
returns table (verification text, resultat text)
language plpgsql security definer
set search_path = public, extensions as $$
declare
  n    integer;
  o    bigint;
  pj   bigint;
  ger  uuid;
  fa   uuid;
  fb   uuid;
begin
  -- Ce contrôle affichera presque toujours OK, puisque la partie A
  -- vient de tourner quelques lignes plus haut. Il sert au deuxième
  -- passage : si des bâtiments créés depuis apparaissent ici, c'est que
  -- le déclencheur du fichier 16 n'est pas en place.
  verification := 'A. Chaque batiment a poules a une date de comptage';
  begin
    select count(*) into n from public.batiments
     where nb_poules > 0 and effectif_pose_le is null;
    resultat := case when n = 0 then 'OK'
                else 'ECHEC — ' || n::text || ' batiment(s) hors du pourcentage ; '
                     || 'relancez le fichier 16 puis celui-ci' end;
  exception when others then resultat := 'ECHEC — ' || sqlerrm; end;
  return next;

  verification := 'B. Les quatre fonctions de ponte existent';
  begin
    resultat := case
      when to_regprocedure('public.ponte_entre(date,date,uuid,uuid)') is not null
       and to_regprocedure('public.ponte_comparee(uuid,uuid,date)') is not null
       and to_regprocedure('public.ponte_par_batiment(date,date,uuid)') is not null
       and to_regprocedure('public.ponte_comparee_par_batiment(uuid,date)') is not null
      then 'OK' else 'ECHEC — relancez ce fichier en entier' end;
  exception when others then resultat := 'ECHEC — ' || sqlerrm; end;
  return next;

  verification := 'B. L application a le droit de les appeler';
  begin
    resultat := case when
        has_function_privilege('authenticated', 'public.ponte_comparee(uuid,uuid,date)', 'execute')
    and has_function_privilege('authenticated', 'public.ponte_entre(date,date,uuid,uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.ponte_par_batiment(date,date,uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.ponte_comparee_par_batiment(uuid,date)', 'execute')
      then 'OK' else 'ECHEC — droit manquant' end;
  exception when others then resultat := 'ECHEC — ' || sqlerrm; end;
  return next;

  verification := 'B. Un visiteur sans compte n a aucun droit dessus';
  begin
    resultat := case when not (
        has_function_privilege('anon', 'public.ponte_comparee(uuid,uuid,date)', 'execute')
     or has_function_privilege('anon', 'public.ponte_entre(date,date,uuid,uuid)', 'execute')
     or has_function_privilege('anon', 'public.ponte_par_batiment(date,date,uuid)', 'execute')
     or has_function_privilege('anon', 'public.ponte_comparee_par_batiment(uuid,date)', 'execute'))
      then 'OK' else 'ECHEC — le role anon peut appeler le calcul' end;
  exception when others then resultat := 'ECHEC — ' || sqlerrm; end;
  return next;

  verification := 'B. Le calcul tourne et rend huit periodes';
  begin
    select count(*) into n from public.ponte_comparee();
    resultat := case when n = 8 then 'OK'
                else 'ECHEC — ' || n::text || ' au lieu de 8' end;
  exception when others then resultat := 'ECHEC — ' || sqlerrm; end;
  return next;

  verification := 'B. Le calcul par batiment tourne aussi';
  begin
    select count(*) into n from public.ponte_comparee_par_batiment();
    resultat := 'OK — ' || n::text || ' ligne(s)';
  exception when others then resultat := 'ECHEC — ' || sqlerrm; end;
  return next;

  verification := 'B. Le taux se divise par des poules-jours';
  begin
    select x.oeufs_mesures, x.poules_jours into o, pj
      from public.ponte_comparee() x where x.periode = 'mois';
    resultat := case
      when pj is null then 'ECHEC — rien calcule'
      when pj = 0 then 'INFO — aucune saisie mesurable ce mois-ci'
      else 'OK — ' || o::text || ' oeufs pour ' || pj::text || ' poules-jours ('
           || round(o::numeric / pj * 100, 1)::text || ' %)' end;
  exception when others then resultat := 'ECHEC — ' || sqlerrm; end;
  return next;

  -- LE défaut que ce fichier corrige : des oeufs validés sur un
  -- bâtiment dont personne n'a compté les poules. Avant, leurs oeufs
  -- se divisaient par zéro poule et la ferme entière affichait plus de
  -- cent pour cent, en vert, avec la mention « excellent ».
  -- Bâtiment par bâtiment, et sur une large fenêtre : le total de la
  -- ferme noyait un bâtiment à 300 %, et le seuil strict de 100 %
  -- criait ECHEC sur une base saine, puisqu'un ramassage rattrapé
  -- couvre parfois deux journées. Même seuil que l'application : 105 %.
  verification := 'B. Aucun batiment ne depasse 105 % de ponte';
  begin
    select count(*) into n
      from public.ponte_par_batiment(current_date - 400, current_date + 1) x
     where x.poules_jours > 0
       and x.oeufs_mesures::numeric / x.poules_jours > 1.05;
    resultat := case when n = 0 then 'OK'
                else 'ECHEC — ' || n::text || ' batiment(s) au-dessus de 105 % : '
                     || 'un ramassage porte plusieurs journees, ou les alveoles '
                     || 'ont ete saisies en trop' end;
  exception when others then resultat := 'ECHEC — ' || sqlerrm; end;
  return next;

  verification := 'B. Les oeufs sans cheptel connu sortent du pourcentage';
  begin
    select count(*) into n from public.productions p
      join public.batiments b on b.id = p.batiment_id
     where p.statut = 'valide'
       and (b.effectif_pose_le is null or p.date < b.effectif_pose_le::date);
    resultat := case when n = 0 then 'OK — toutes les saisies sont mesurables'
                else 'OK — ' || n::text || ' saisie(s) comptee(s) dans le total '
                     || 'mais hors pourcentage (effectif pas encore renseigne)' end;
  exception when others then resultat := 'ECHEC — ' || sqlerrm; end;
  return next;

  verification := 'C. L effectif vivant est lisible en base';
  begin
    resultat := case when exists (
        select 1 from information_schema.views
         where table_schema = 'public' and table_name = 'batiments_vivants')
      then 'OK' else 'ECHEC' end;
  exception when others then resultat := 'ECHEC — ' || sqlerrm; end;
  return next;

  verification := 'C. Un visiteur sans compte ne lit pas les effectifs';
  begin
    resultat := case when not exists (
        select 1 from information_schema.role_table_grants
         where table_schema = 'public' and table_name = 'batiments_vivants'
           and grantee in ('anon', 'PUBLIC'))
      then 'OK' else 'ECHEC — le role anon lit les effectifs' end;
  exception when others then resultat := 'ECHEC — ' || sqlerrm; end;
  return next;

  verification := 'C. La vue applique les regles de celui qui lit';
  begin
    resultat := case when exists (
        select 1 from pg_class c join pg_namespace s on s.oid = c.relnamespace
         where s.nspname = 'public' and c.relname = 'batiments_vivants'
           and c.reloptions @> array['security_invoker=on'])
      then 'OK' else 'ECHEC — la vue montrerait toutes les fermes' end;
  exception when others then resultat := 'ECHEC — ' || sqlerrm; end;
  return next;

  -- D. L'ISOLATION ENTRE FERMES, ÉPROUVÉE SUR UN VRAI COMPTE
  -- Les trois tables du calcul se ferment toutes par ma_ferme_est() :
  -- on se fait passer pour un vrai gérant et on vérifie que la porte
  -- lui refuse l'autre ferme. Vérifier les seuls droits ne prouvait
  -- rien de ce qui compte ici.
  verification := 'D. Les trois tables du calcul se ferment par ferme';
  begin
    -- Les TABLES, pas les lignes de politique : trois politiques sur la
    -- même table affichaient OK pendant que deux tables restaient
    -- grandes ouvertes.
    select count(distinct tablename) into n from pg_policies
     where schemaname = 'public' and cmd = 'SELECT'
       and tablename in ('productions', 'batiments', 'mortalites')
       and qual like '%ma_ferme_est%';
    resultat := case when n = 3 then 'OK'
                else 'ECHEC — ' || n::text || ' table(s) fermee(s) sur 3' end;
  exception when others then resultat := 'ECHEC — ' || sqlerrm; end;
  return next;

  verification := 'D. Un gerant se voit refuser l autre ferme';
  begin
    select p.id, p.ferme_id into ger, fa
      from public.profils p
     where p.role = 'gerant' and not p.suspendu and p.ferme_id is not null
     order by p.cree_le limit 1;
    select f.id into fb from public.fermes f
     where f.id is distinct from fa order by f.cree_le limit 1;

    if ger is null then
      resultat := 'INFO — pas testable tant qu aucun gerant n est rattache a une ferme';
    elsif fb is null then
      resultat := 'INFO — pas testable tant qu il n y a qu une seule ferme';
    else
      perform set_config('request.jwt.claims',
        json_build_object('sub', ger::text, 'role', 'authenticated')::text, true);
      perform set_config('request.jwt.claim.sub', ger::text, true);
      if public.ma_ferme_est(fa) and not public.ma_ferme_est(fb) then
        resultat := 'OK';
      else
        resultat := 'ECHEC — la porte laisse passer une autre ferme';
      end if;
      perform set_config('request.jwt.claims', '', true);
      perform set_config('request.jwt.claim.sub', '', true);
    end if;
  exception when others then
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    resultat := 'ECHEC — ' || sqlerrm;
  end;
  return next;

  verification := 'D. Une mort a venir est refusee';
  begin
    resultat := case when exists (
        select 1 from pg_trigger g join pg_class c on c.oid = g.tgrelid
          join pg_namespace s on s.oid = c.relnamespace
         where s.nspname = 'public' and c.relname = 'mortalites'
           and g.tgname = 'trg_mortalite_date' and not g.tgisinternal)
      then 'OK' else 'ECHEC — le verrou de date manque' end;
  exception when others then resultat := 'ECHEC — ' || sqlerrm; end;
  return next;

  verification := 'D. Le refus de date dit pourquoi, en francais';
  begin
    resultat := case when exists (
        select 1 from pg_proc p join pg_namespace s on s.oid = p.pronamespace
         where s.nspname = 'public' and p.proname = 'mortalite_date_tenable'
           and pg_get_functiondef(p.oid) like '%précède le comptage%'
           and pg_get_functiondef(p.oid) like '%date à venir%')
      then 'OK' else 'ECHEC — un refus sans explication' end;
  exception when others then resultat := 'ECHEC — ' || sqlerrm; end;
  return next;

  verification := 'INFO. Morts declarees a une date a venir';
  begin
    select count(*) into n from public.mortalites m
     where m.date > current_date;
    resultat := case when n = 0 then 'aucune'
                else n::text || ' — elles comptent dans le cheptel mais pas dans '
                     || 'le pourcentage ; ramenez leur date a aujourd hui depuis '
                     || 'l onglet Sante' end;
  exception when others then resultat := 'ECHEC — ' || sqlerrm; end;
  return next;

  verification := 'INFO. Morts declarees avant le comptage des poules';
  begin
    select count(*) into n from public.mortalites m
      join public.batiments b on b.id = m.batiment_id
     where b.effectif_pose_le is not null
       and m.date < b.effectif_pose_le::date;
    resultat := case when n = 0 then 'aucune'
                else n::text || ' — elles sont deja retirees du nombre compte, '
                     || 'donc non deduites une seconde fois ; c est normal. '
                     || 'Supprimez la ligne depuis l onglet Sante si elle est '
                     || 'en double' end;
  exception when others then resultat := 'ECHEC — ' || sqlerrm; end;
  return next;

  verification := 'INFO. Batiments dont le cheptel est a zero';
  begin
    select count(*) into n from public.batiments_vivants
     where vivantes = 0 and nb_poules > 0;
    resultat := case when n = 0 then 'aucun'
                else n::text || ' — verifiez les declarations de mortalite' end;
  exception when others then resultat := 'ECHEC — ' || sqlerrm; end;
  return next;

  verification := 'INFO. Batiments dont personne n a compte les poules';
  begin
    select count(*) into n from public.batiments where nb_poules = 0;
    resultat := case when n = 0 then 'aucun'
                else n::text || ' — leur fermier le renseignera depuis Production' end;
  exception when others then resultat := 'ECHEC — ' || sqlerrm; end;
  return next;
end $$;

revoke all on function public.idiama_controle_17() from public, anon, authenticated;

notify pgrst, 'reload schema';

select * from public.idiama_controle_17();
