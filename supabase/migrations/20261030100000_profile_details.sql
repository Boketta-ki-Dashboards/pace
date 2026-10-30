-- =============================================================================================================
-- Pace – Social-Profil 2.0 (Auftrag 6): Bio, Interessen, Profilbanner und freiwillige Auszeichnungen.
--
-- Alles optional und additiv: Bestehende Profile behalten ihre Daten, die neuen Spalten haben Standardwerte (leer).
-- Die App funktioniert auch ohne diese Migration (sie zeigt die neuen Felder dann nicht an und bietet sie nicht zum
-- Bearbeiten an).
--
-- * profiles.bio: höchstens 160 Zeichen, höchstens 4 Zeilen, ohne Steuer- und unsichtbare Formatzeichen (wie
--   display_name). Spiegelt PaceCore.ProfileBioRules.
-- * profiles.interests: bis zu 5 Interessen aus einem festen Katalog (stabile IDs, die App übersetzt sie).
-- * profiles.banner_path: Profilbanner im privaten Bucket avatars, im Ordner der eigenen public_id (wie das
--   Profilbild, gleiche Größengrenze 5 MB). Lesen dürfen es – wie das aktuelle Profilbild – alle Angemeldeten mit
--   Profil, außer die Besitzerin hat sie blockiert (pace_access.can_read_avatar, hier ergänzt).
-- * profiles.shows_achievements / achievements: freiwillig sichtbare Auszeichnungen (Serien-Meilensteine, Bestwert-
--   Stufen) – ohne genaue Schrittzahlen. Standard: nicht sichtbar. Die App ermittelt sie aus ihrem vorhandenen
--   Serien- und Bestwert-Modell; der Server prüft nur den Katalog.
-- * social_profile_details(public_id): die neuen Felder einer Person mit denselben Sichtbarkeitsregeln wie
--   social_public_profile (nicht sichtbar → not_found). Ist eine der beiden Personen blockiert, kommen keine
--   persönlichen Angaben (Bio, Interessen, Banner, Auszeichnungen) mit.
-- * Ändern: direkt in der eigenen Zeile (RLS wie bisher: nur die eigene Zeile).
-- =============================================================================================================

alter table public.profiles
  add column bio text,
  add column interests text[] not null default '{}',
  add column banner_path text,
  add column shows_achievements boolean not null default false,
  add column achievements text[] not null default '{}';

comment on column public.profiles.bio is 'Kurzer Text über sich (max. 160 Zeichen, max. 4 Zeilen). null = keine Bio.';
comment on column public.profiles.interests is 'Bis zu 5 Interessen aus dem Katalog (stabile IDs).';
comment on column public.profiles.banner_path is
  'Profilbanner im privaten Bucket avatars: <public_id>/<Name>.<jpg|jpeg|png|heic|webp>. null = neutraler Hintergrund.';
comment on column public.profiles.shows_achievements is 'Freiwillig: Auszeichnungen auf dem Profil zeigen. Standard: aus.';
comment on column public.profiles.achievements is
  'Auszeichnungen aus dem Katalog (Serien-Meilensteine, Bestwert-Stufen, keine genauen Werte).';

alter table public.profiles add constraint profiles_bio_valid check (
  bio is null or (
    char_length(bio) between 1 and 160
    and bio = btrim(bio, E' \n')
    -- Zeilenumbrüche erlaubt (höchstens 3), sonst keine Steuerzeichen.
    and regexp_replace(bio, E'\n', '', 'g') !~ '[[:cntrl:]]'
    and cardinality(string_to_array(bio, E'\n')) <= 4
    -- Unsichtbare Formatzeichen wie beim Anzeigenamen – außer dem Zero-Width-Joiner (U+200D), den Emoji-Folgen
    -- (z. B. Person beim Gehen mit Geschlecht) brauchen.
    and bio !~ '[\u0080-\u009F\u00AD\u0600-\u0605\u061C\u06DD\u070F\u180E\u200B\u200C\u200E\u200F\u202A-\u202E\u2060-\u2064\u2066-\u206F\uFEFF\uFFF9-\uFFFB\U000E0001\U000E0020-\U000E007F]'
  )
);

alter table public.profiles add constraint profiles_interests_valid check (
  cardinality(interests) <= 5
  and interests <@ array['walking', 'running', 'hiking', 'fitness', 'cycling', 'football', 'outdoor',
                         'everyday_movement', 'challenges', 'wellbeing']::text[]
);

alter table public.profiles add constraint profiles_banner_path_format check (
  banner_path is null
  or banner_path ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[A-Za-z0-9_-]{1,64}\.(jpg|jpeg|png|heic|webp)$'
);

alter table public.profiles add constraint profiles_achievements_valid check (
  cardinality(achievements) <= 7
  and achievements <@ array['streak_7', 'streak_30', 'streak_100', 'streak_365',
                            'best_day_10k', 'best_day_20k', 'best_day_30k']::text[]
);

-- Keine doppelten Einträge (Check-Constraints erlauben keine Unterabfragen; der Trigger läuft unabhängig von den
-- Rechten des Aufrufers).
create function private.validate_profile_details()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select count(*) <> count(distinct v) from unnest(new.interests) as v) then
    raise exception 'invalid_interests' using errcode = '23514';
  end if;
  if (select count(*) <> count(distinct v) from unnest(new.achievements) as v) then
    raise exception 'invalid_achievements' using errcode = '23514';
  end if;
  return new;
end;
$$;
revoke all on function private.validate_profile_details() from public, anon, authenticated;

create trigger profiles_validate_details
  before insert or update of interests, achievements on public.profiles
  for each row execute function private.validate_profile_details();

-- Die App ändert die neuen Felder direkt in der eigenen Zeile (RLS: nur eigene Zeile).
grant update (bio, interests, banner_path, shows_achievements, achievements) on table public.profiles to authenticated;

-- Banner: nur im Ordner der eigenen public_id und nur, wenn die Datei im Bucket avatars existiert (wie das
-- Profilbild, 20261019100000_profiles_blocks_search.sql).
create function private.validate_profile_banner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.banner_path is not null
     and (tg_op = 'INSERT' or new.banner_path is distinct from old.banner_path) then
    if split_part(new.banner_path, '/', 1) <> new.public_id::text
       or not exists (
         select 1 from storage.objects o where o.bucket_id = 'avatars' and o.name = new.banner_path
       ) then
      raise exception 'invalid_banner_path' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.validate_profile_banner() from public, anon, authenticated;

create trigger profiles_validate_banner
  before insert or update of banner_path on public.profiles
  for each row execute function private.validate_profile_banner();

-- ---------------------------------------------------------------------------------------------------------------
-- Storage: Das aktuelle Banner ist wie das aktuelle Profilbild für Angemeldete lesbar
-- ---------------------------------------------------------------------------------------------------------------

-- Ersetzt die Fassung aus 20261019100300_storage_realtime_access.sql: zusätzlich owner.banner_path = p_name.
create or replace function pace_access.can_read_avatar(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.profiles owner
     where owner.public_id = pace_access.object_folder(p_name)
       and (
         owner.id = auth.uid()
         or (
           (owner.avatar_path = p_name or owner.banner_path = p_name)
           and exists (select 1 from public.profiles me where me.id = auth.uid())
           and not private.has_blocked(owner.id, auth.uid())
         )
       )
  );
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- RPC: Profilangaben einer Person
-- ---------------------------------------------------------------------------------------------------------------

create function public.social_profile_details(p_public_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
  v_target public.profiles%rowtype;
begin
  perform private.consume_rate_limit(v_me, 'profile_details', 120, interval '10 minutes');
  select * into v_target from public.profiles p where p.public_id = p_public_id;
  -- Gleiche Sichtbarkeit wie social_public_profile: wer mich blockiert hat oder nicht sichtbar ist → not_found.
  if not found or not private.can_view_profile(v_me, v_target.id) then
    raise exception 'not_found';
  end if;

  -- Eigenes Profil: alles, auch die Einstellung zu den Auszeichnungen.
  if v_target.id = v_me then
    return jsonb_build_object(
      'bio', v_target.bio,
      'interests', to_jsonb(v_target.interests),
      'banner_path', v_target.banner_path,
      'shows_achievements', v_target.shows_achievements,
      'achievements', to_jsonb(v_target.achievements)
    );
  end if;

  -- Blockierung in einer der beiden Richtungen: keine persönlichen Angaben.
  if private.is_blocked(v_me, v_target.id) then
    return jsonb_build_object('bio', null, 'interests', '[]'::jsonb, 'banner_path', null, 'achievements', '[]'::jsonb);
  end if;

  return jsonb_build_object(
    'bio', v_target.bio,
    'interests', to_jsonb(v_target.interests),
    'banner_path', v_target.banner_path,
    'achievements', case when v_target.shows_achievements then to_jsonb(v_target.achievements) else '[]'::jsonb end
  );
end;
$$;
revoke all on function public.social_profile_details(uuid) from public, anon;
grant execute on function public.social_profile_details(uuid) to authenticated;
comment on function public.social_profile_details(uuid) is
  'Pace: Bio, Interessen, Banner und – nur wenn freigegeben – Auszeichnungen einer Person. not_found wie social_public_profile; bei Blockierung leer. Max. 120 je 10 Minuten.';
