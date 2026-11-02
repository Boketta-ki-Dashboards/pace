-- =============================================================================================================
-- Pace – Interessen 2.0 (Auftrag 7): größerer Katalog in Kategorien, eigene Interessen, gesprochene Sprachen und ein
-- freiwilliger Länder- bzw. Kulturbezug.
--
-- Additiv und kompatibel mit 20261030100000_profile_details.sql (bereits produktiv, bleibt unverändert):
-- * Bestehende Interessen behalten ihre IDs und bleiben gültig – es werden keine Daten umgeschrieben oder gelöscht.
-- * Neue Spalten mit Standardwerten (leer bzw. null): alte Profile bleiben, wie sie sind.
-- * social_profile_details liefert zusätzlich custom_interests, spoken_languages und country_code. Ältere
--   App-Versionen ignorieren die neuen Schlüssel; die neue App erkennt an ihnen, dass der Server die Erweiterung kennt.
--   Ohne diese Migration bleibt die neue App bei höchstens fünf Interessen aus dem ursprünglichen Katalog.
--
-- * private.profile_interest_catalog: stabile IDs mit Kategorie. Ein neues Interesse = eine neue Zeile hier und eine in
--   der App (PaceCore.ProfileInterest) – kein neuer Constraint, keine neue Spalte. Nicht über die API erreichbar.
-- * profiles.interests: Katalog-IDs, geprüft per Trigger gegen die Katalogtabelle (vorher festes Array im Constraint).
-- * profiles.custom_interests: selbst eingegebene Begriffe – 2 bis 30 Zeichen, ohne Leerzeichen am Rand und doppelte
--   Leerzeichen, ohne Steuer- und unsichtbare Formatzeichen (wie die Bio), ohne Links, E-Mail-Adressen und @, Unicode-NFC,
--   keine Doppelten ohne Rücksicht auf Groß-/Kleinschreibung. Sie gehören nur zum eigenen Profil, werden nie Teil des
--   Katalogs und lassen sich über die bestehende Meldefunktion melden (Schnappschuss erweitert).
-- * Katalog-Interessen und eigene zusammen höchstens 20.
-- * profiles.spoken_languages: bis zu 10 ISO-639-Codes (2–3 Kleinbuchstaben), ohne Doppelte. Freiwillig, nie aus der
--   App-Sprache abgeleitet.
-- * profiles.country_code: optionaler ISO-3166-Code (zwei Großbuchstaben) – freiwillige Selbstbeschreibung, nicht
--   geprüft. Ohne Einfluss auf Regionen und Ranglisten (die beruhen weiter allein auf region_id).
-- * Sichtbarkeit wie Bio und Interessen: social_profile_details (can_view_profile, bei Blockierung leer). Keine
--   Weitergabe an Gruppen, Freundeslisten oder Ranglisten (private.profile_json bleibt unverändert).
-- * Datenexport (account_export) enthält die neuen Spalten automatisch (to_jsonb der eigenen Zeile).
-- =============================================================================================================

-- ---------------------------------------------------------------------------------------------------------------
-- Katalog
-- ---------------------------------------------------------------------------------------------------------------

create table private.profile_interest_catalog (
  id text primary key check (id ~ '^[a-z][a-z_]{1,39}$'),
  category text not null check (category in ('sport', 'creative', 'tech', 'leisure', 'culture')),
  sort_order integer not null
);
comment on table private.profile_interest_catalog is
  'Interessenkatalog (stabile IDs, die App übersetzt). Neue Interessen: neue Zeile, keine Schemaänderung.';
revoke all on table private.profile_interest_catalog from public, anon, authenticated;

-- Alle zehn bisherigen IDs bleiben enthalten (walking, running, hiking, fitness, cycling, football, outdoor,
-- everyday_movement, challenges, wellbeing).
insert into private.profile_interest_catalog (id, category, sort_order) values
  ('football', 'sport', 10),
  ('basketball', 'sport', 20),
  ('volleyball', 'sport', 30),
  ('fitness', 'sport', 40),
  ('running', 'sport', 50),
  ('walking', 'sport', 60),
  ('hiking', 'sport', 70),
  ('cycling', 'sport', 80),
  ('swimming', 'sport', 90),
  ('martial_arts', 'sport', 100),
  ('dancing', 'sport', 110),
  ('skateboarding', 'sport', 120),
  ('tennis', 'sport', 130),
  ('yoga', 'sport', 140),
  ('outdoor', 'sport', 150),
  ('everyday_movement', 'sport', 160),
  ('challenges', 'sport', 170),
  ('wellbeing', 'sport', 180),
  ('rap', 'creative', 190),
  ('hip_hop', 'creative', 200),
  ('making_music', 'creative', 210),
  ('singing', 'creative', 220),
  ('freestyle', 'creative', 230),
  ('music_production', 'creative', 240),
  ('djing', 'creative', 250),
  ('drawing', 'creative', 260),
  ('photography', 'creative', 270),
  ('design', 'creative', 280),
  ('programming', 'tech', 290),
  ('web_development', 'tech', 300),
  ('app_development', 'tech', 310),
  ('ai', 'tech', 320),
  ('gaming', 'tech', 330),
  ('game_development', 'tech', 340),
  ('technology', 'tech', 350),
  ('content_creation', 'tech', 360),
  ('travel', 'leisure', 370),
  ('cars', 'leisure', 380),
  ('fashion', 'leisure', 390),
  ('cooking', 'leisure', 400),
  ('movies', 'leisure', 410),
  ('series', 'leisure', 420),
  ('books', 'leisure', 430),
  ('nature', 'leisure', 440),
  ('animals', 'leisure', 450),
  ('language_learning', 'culture', 460),
  ('multilingualism', 'culture', 470),
  ('culture', 'culture', 480),
  ('history', 'culture', 490),
  ('international_friendships', 'culture', 500);

-- ---------------------------------------------------------------------------------------------------------------
-- Neue Spalten
-- ---------------------------------------------------------------------------------------------------------------

alter table public.profiles
  add column custom_interests text[] not null default '{}',
  add column spoken_languages text[] not null default '{}',
  add column country_code text;

comment on column public.profiles.interests is 'Interessen aus private.profile_interest_catalog (stabile IDs).';
comment on column public.profiles.custom_interests is
  'Selbst eingegebene Interessen (2–30 Zeichen, normalisiert, ohne Doppelte). Mit interests zusammen max. 20.';
comment on column public.profiles.spoken_languages is
  'Freiwillig: gesprochene Sprachen als ISO-639-Codes (max. 10). Nie aus der App-Sprache abgeleitet.';
comment on column public.profiles.country_code is
  'Freiwillig: Land bzw. Kulturbezug als ISO-3166-Code. Selbstbeschreibung, nicht geprüft, ohne Einfluss auf Ranglisten.';

-- Bisher: höchstens 5 aus einem festen Array. Jetzt: zusammen mit eigenen höchstens 20; der Katalog wird im Trigger
-- gegen private.profile_interest_catalog geprüft (Check-Constraints erlauben keine Unterabfragen).
alter table public.profiles drop constraint profiles_interests_valid;

alter table public.profiles add constraint profiles_interests_total check (
  cardinality(interests) + cardinality(custom_interests) <= 20
  and coalesce(array_ndims(interests), 1) = 1
  and coalesce(array_ndims(custom_interests), 1) = 1
  and array_position(interests, null) is null
  and array_position(custom_interests, null) is null
);

alter table public.profiles add constraint profiles_spoken_languages_valid check (
  cardinality(spoken_languages) <= 10
  and coalesce(array_ndims(spoken_languages), 1) = 1
  and array_position(spoken_languages, null) is null
  and array_to_string(spoken_languages, ',') ~ '^([a-z]{2,3}(,[a-z]{2,3})*)?$'
);

alter table public.profiles add constraint profiles_country_code_valid check (
  country_code is null or country_code ~ '^[A-Z]{2}$'
);

-- ---------------------------------------------------------------------------------------------------------------
-- Prüfung: Katalog, eigene Interessen, keine Doppelten
-- ---------------------------------------------------------------------------------------------------------------

-- Ersetzt die Fassung aus 20261030100000_profile_details.sql (dort nur: keine doppelten Interessen und Auszeichnungen).
create or replace function private.validate_profile_details()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Katalog-Interessen: nur bekannte IDs, keine Doppelten.
  if (select count(*) <> count(distinct v) from unnest(new.interests) as v)
     or exists (
       select 1 from unnest(new.interests) as v
        where not exists (select 1 from private.profile_interest_catalog c where c.id = v)
     ) then
    raise exception 'invalid_interests' using errcode = '23514';
  end if;

  -- Eigene Interessen: Länge, Leerzeichen, Zeichen, keine Links; keine Doppelten ohne Rücksicht auf Groß-/Kleinschreibung.
  if exists (
       select 1 from unnest(new.custom_interests) as v
        where v is null
           or char_length(v) not between 2 and 30
           or v <> btrim(v)
           or v ~ '\s\s'
           or v ~ '[[:cntrl:]]'
           or v ~ '[\u0080-\u009F\u00AD\u0600-\u0605\u061C\u06DD\u070F\u180E\u200B\u200C\u200E\u200F\u202A-\u202E\u2060-\u2064\u2066-\u206F\uFEFF\uFFF9-\uFFFB\U000E0001\U000E0020-\U000E007F]'
           or v ~* '(://|www\.|@)'
           or not (v is nfc normalized)
     )
     or (select count(*) <> count(distinct lower(v)) from unnest(new.custom_interests) as v) then
    raise exception 'invalid_custom_interests' using errcode = '23514';
  end if;

  if (select count(*) <> count(distinct v) from unnest(new.spoken_languages) as v) then
    raise exception 'invalid_spoken_languages' using errcode = '23514';
  end if;
  if (select count(*) <> count(distinct v) from unnest(new.achievements) as v) then
    raise exception 'invalid_achievements' using errcode = '23514';
  end if;
  return new;
end;
$$;
revoke all on function private.validate_profile_details() from public, anon, authenticated;

drop trigger profiles_validate_details on public.profiles;
create trigger profiles_validate_details
  before insert or update of interests, custom_interests, spoken_languages, achievements on public.profiles
  for each row execute function private.validate_profile_details();

-- Die App ändert die neuen Felder direkt in der eigenen Zeile (RLS wie bisher: nur die eigene Zeile).
grant update (custom_interests, spoken_languages, country_code) on table public.profiles to authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- RPC: Profilangaben einer Person – zusätzlich eigene Interessen, Sprachen und Land
-- ---------------------------------------------------------------------------------------------------------------

-- Ersetzt die Fassung aus 20261030100000_profile_details.sql: gleiche Sichtbarkeit und Rate-Limit, gleiche Schlüssel,
-- zusätzlich custom_interests, spoken_languages, country_code (bei Blockierung leer bzw. null).
create or replace function public.social_profile_details(p_public_id uuid)
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
      'custom_interests', to_jsonb(v_target.custom_interests),
      'spoken_languages', to_jsonb(v_target.spoken_languages),
      'country_code', v_target.country_code,
      'banner_path', v_target.banner_path,
      'shows_achievements', v_target.shows_achievements,
      'achievements', to_jsonb(v_target.achievements)
    );
  end if;

  -- Blockierung in einer der beiden Richtungen: keine persönlichen Angaben.
  if private.is_blocked(v_me, v_target.id) then
    return jsonb_build_object(
      'bio', null, 'interests', '[]'::jsonb, 'custom_interests', '[]'::jsonb, 'spoken_languages', '[]'::jsonb,
      'country_code', null, 'banner_path', null, 'achievements', '[]'::jsonb
    );
  end if;

  return jsonb_build_object(
    'bio', v_target.bio,
    'interests', to_jsonb(v_target.interests),
    'custom_interests', to_jsonb(v_target.custom_interests),
    'spoken_languages', to_jsonb(v_target.spoken_languages),
    'country_code', v_target.country_code,
    'banner_path', v_target.banner_path,
    'achievements', case when v_target.shows_achievements then to_jsonb(v_target.achievements) else '[]'::jsonb end
  );
end;
$$;
revoke all on function public.social_profile_details(uuid) from public, anon;
grant execute on function public.social_profile_details(uuid) to authenticated;
comment on function public.social_profile_details(uuid) is
  'Pace: Bio, Interessen (Katalog und eigene), Sprachen, Land, Banner und – nur wenn freigegeben – Auszeichnungen einer Person. not_found wie social_public_profile; bei Blockierung leer. Max. 120 je 10 Minuten.';

-- ---------------------------------------------------------------------------------------------------------------
-- Meldungen: eigene Interessen, Sprachen und Land im Schnappschuss
-- ---------------------------------------------------------------------------------------------------------------

-- Ersetzt die Fassung aus 20261030100000_profile_details.sql unverändert bis auf den Schnappschuss einer gemeldeten
-- Person (zusätzlich custom_interests, spoken_languages, country_code).
create or replace function public.social_report(p_target_type text, p_target_id uuid, p_reason text, p_details text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_profile();
  v_details text := nullif(btrim(coalesce(p_details, ''), E' \t\n\r'), '');
  v_snapshot jsonb;
  v_target_user uuid;
  v_message public.chat_messages%rowtype;
begin
  if p_target_id is null then
    raise exception 'not_found';
  end if;

  case p_target_type
    when 'user' then
      -- Jede bekannte Person außer mir selbst (auch nach einer Blockierung, z. B. wegen Belästigung davor).
      -- Seit Social-Profil 2.0 mit Bio, Interessen und Banner, seit Interessen 2.0 auch mit eigenen Interessen,
      -- Sprachen und Land: nutzergenerierter Inhalt, der sich sonst nach der Meldung spurlos ändern ließe.
      select p.id,
             (private.profile_json(p) - 'nickname')
               || jsonb_build_object('bio', p.bio, 'interests', to_jsonb(p.interests), 'banner_path', p.banner_path,
                                     'custom_interests', to_jsonb(p.custom_interests),
                                     'spoken_languages', to_jsonb(p.spoken_languages), 'country_code', p.country_code)
        into v_target_user, v_snapshot
        from public.profiles p
       where p.public_id = p_target_id;
      if v_target_user is null or v_target_user = v_me then
        raise exception 'not_found';
      end if;
    when 'message' then
      -- Nur Nachrichten anderer in Unterhaltungen, die ich lesen darf.
      select * into v_message from public.chat_messages m where m.id = p_target_id and m.deleted_at is null;
      if not found
         or v_message.sender_id is not distinct from v_me
         or not private.can_read_conversation(v_message.conversation_id, v_me) then
        raise exception 'not_found';
      end if;
      v_snapshot := jsonb_build_object(
        'conversation_id', v_message.conversation_id,
        'kind', v_message.kind,
        'body', v_message.body,
        'media_path', v_message.media_path,
        'sender', (select private.profile_json(s) - 'nickname' from public.profiles s where s.id = v_message.sender_id),
        'created_at', v_message.created_at
      );
    when 'group' then
      -- Gruppen, in denen ich Mitglied bin oder in die ich eingeladen wurde.
      if private.group_role(p_target_id, v_me) is null
         and not exists (
           select 1 from public.group_invitations i
            where i.group_id = p_target_id and i.invitee_id = v_me and i.status = 'pending'
         ) then
        raise exception 'not_found';
      end if;
      select jsonb_build_object('name', g.name, 'description', g.description, 'image_path', g.image_path)
        into v_snapshot
        from public.groups g
       where g.id = p_target_id;
    else
      raise exception 'invalid_input';
  end case;

  if p_reason is null
     or p_reason not in ('spam', 'harassment', 'inappropriate', 'impersonation', 'other')
     or (v_details is not null and char_length(v_details) > 1000) then
    raise exception 'invalid_input';
  end if;

  -- Erneutes Melden desselben Ziels, solange die Meldung offen ist, ist unschädlich und zählt nicht.
  if exists (
    select 1 from public.reports r
     where r.reporter_id = v_me and r.target_type = p_target_type and r.target_id = p_target_id and r.status = 'open'
  ) then
    return;
  end if;
  perform private.consume_rate_limit(v_me, 'report', 10, interval '24 hours');

  insert into public.reports (reporter_id, target_type, target_id, reason, details, target_snapshot)
  values (v_me, p_target_type, p_target_id, p_reason, v_details, coalesce(v_snapshot, '{}'::jsonb))
  on conflict (reporter_id, target_type, target_id) where status = 'open' do nothing;
end;
$$;
revoke all on function public.social_report(text, uuid, text, text) from public, anon;
grant execute on function public.social_report(text, uuid, text, text) to authenticated;
