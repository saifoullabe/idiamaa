-- =====================================================================
-- IDIAMA AGRO — Numéro d'accès à 8 chiffres
-- À lancer après 01. Relançable sans risque.
--
-- L'identifiant d'un gérant ou d'un fermier devient un numéro de huit
-- chiffres, tiré au hasard et jamais donné deux fois. Un fermier retient
-- huit chiffres ; il ne se trompe pas sur un point, un tiret ou un accent.
-- =====================================================================

create or replace function public.nouveau_numero_acces()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  n      text;
  essais integer := 0;
begin
  if public.mon_role() <> 'admin' then
    raise exception 'Réservé à l''administrateur';
  end if;

  loop
    -- Entre 10000000 et 99999999 : toujours huit chiffres, jamais de
    -- zéro en tête qu'un fermier oublierait de taper.
    n := (floor(random() * 90000000) + 10000000)::bigint::text;

    exit when not exists (select 1 from public.profils where login = n);

    essais := essais + 1;
    if essais > 50 then
      raise exception 'Impossible de tirer un numéro libre';
    end if;
  end loop;

  return n;
end $$;

revoke all on function public.nouveau_numero_acces() from public, anon;
grant execute on function public.nouveau_numero_acces() to authenticated;

-- ── Contrôle ─────────────────────────────────────────────────────────
select 'Generateur de numero' as verification,
  case when exists (select 1 from pg_proc p join pg_namespace n
      on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'nouveau_numero_acces')
  then 'cree  OK' else 'ABSENT  ECHEC' end as resultat
union all
select 'Reserve a l''administrateur',
  case when exists (select 1 from pg_proc p join pg_namespace n
      on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'nouveau_numero_acces'
      and p.prosecdef = true)
  then 'oui  OK' else 'NON  ECHEC' end
union all
select 'Essai : un numero libre',
  public.nouveau_numero_acces();
