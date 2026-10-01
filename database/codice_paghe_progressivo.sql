CREATE OR REPLACE FUNCTION public.amministrativo_assegna_codice_paghe() RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
BEGIN
 IF NEW."CodicePaghe" = '__AUTO_NEXUS__' THEN
  NEW."CodicePaghe" := NEW."ID_DipendenteEsterno"::text;
 END IF;
 RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION public.amministrativo_assegna_codice_paghe() FROM PUBLIC, anon, authenticated;
-- Existing payroll codes are preserved. New administrative store inserts use the external ID as payroll code.
