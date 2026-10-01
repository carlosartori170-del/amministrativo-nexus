BEGIN;
CREATE SEQUENCE public.amministrativo_codice_paghe_seq AS bigint START WITH 23464;
GRANT USAGE ON SEQUENCE public.amministrativo_codice_paghe_seq TO authenticated;
CREATE FUNCTION public.amministrativo_assegna_codice_paghe() RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
DECLARE candidate bigint;
BEGIN
 IF NEW."CodicePaghe" = '__AUTO_NEXUS__' THEN
  LOOP
   candidate := nextval('public.amministrativo_codice_paghe_seq'::regclass);
   EXIT WHEN NOT EXISTS (SELECT 1 FROM public."PersoneRete" WHERE trim("CodicePaghe") ~ '^[0-9]+$' AND CASE WHEN trim("CodicePaghe") ~ '^[0-9]+$' THEN trim("CodicePaghe")::numeric END = candidate);
  END LOOP;
  NEW."CodicePaghe" := candidate::text;
 END IF;
 RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION public.amministrativo_assegna_codice_paghe() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER amministrativo_codice_paghe_insert BEFORE INSERT ON public."PersoneRete" FOR EACH ROW EXECUTE FUNCTION public.amministrativo_assegna_codice_paghe();
COMMIT;