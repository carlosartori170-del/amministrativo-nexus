BEGIN;
CREATE OR REPLACE FUNCTION public.amministrativo_blocca_codice_paghe() RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE existing_code text;
BEGIN
 existing_code:=nullif(trim(OLD."CodicePaghe"),'');
 IF TG_TABLE_NAME='Dipendenti' AND existing_code IS NULL THEN existing_code:=OLD."CodiceVoice"::text; END IF;
 IF existing_code IS NOT NULL THEN
  IF nullif(trim(NEW."CodicePaghe"),'') IS DISTINCT FROM nullif(trim(OLD."CodicePaghe"),'') THEN
   RAISE EXCEPTION 'Il codice paghe già registrato non può essere modificato';
  END IF;
  IF TG_TABLE_NAME='Dipendenti' THEN
   IF nullif(trim(OLD."CodicePaghe"),'') IS NULL AND NEW."CodiceVoice" IS DISTINCT FROM OLD."CodiceVoice" THEN NEW."CodicePaghe":=existing_code; END IF;
  END IF;
 END IF;
 RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION public.amministrativo_blocca_codice_paghe() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER amministrativo_paghe_immutabile BEFORE UPDATE ON public."Dipendenti" FOR EACH ROW EXECUTE FUNCTION public.amministrativo_blocca_codice_paghe();
CREATE TRIGGER amministrativo_paghe_immutabile BEFORE UPDATE ON public."PersoneRete" FOR EACH ROW EXECUTE FUNCTION public.amministrativo_blocca_codice_paghe();
COMMIT;