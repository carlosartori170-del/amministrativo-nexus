BEGIN;
ALTER TABLE public."Dipendenti" ADD COLUMN IF NOT EXISTS "CodicePaghe" text;
CREATE SEQUENCE public.amministrativo_paghe_tre_cifre_seq AS integer MINVALUE 100 MAXVALUE 999 START 206 NO CYCLE;
GRANT USAGE ON SEQUENCE public.amministrativo_paghe_tre_cifre_seq TO authenticated;
CREATE FUNCTION public.amministrativo_genera_codice_paghe() RETURNS text LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE candidate integer;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM public."NexusProfili" p WHERE p."UserID"=auth.uid() AND p."Attivo" AND p."Ruolo"='admin' AND p."Magazzini_Accessibili" @> ARRAY(SELECT "ID_Magazzino" FROM public."Magazzini")) THEN
  RAISE EXCEPTION 'Generazione riservata agli amministratori con accesso a tutti i magazzini';
 END IF;
 LOOP
  BEGIN candidate:=nextval('public.amministrativo_paghe_tre_cifre_seq'::regclass);
  EXCEPTION WHEN sequence_generator_limit_exceeded THEN RAISE EXCEPTION 'Codici a tre cifre esauriti: occorre configurare un nuovo intervallo'; END;
  EXIT WHEN NOT EXISTS(SELECT 1 FROM public."Dipendenti" WHERE "CodiceVoice"=candidate OR CASE WHEN trim("CodicePaghe") ~ '^[0-9]+$' THEN trim("CodicePaghe")::numeric END=candidate)
   AND NOT EXISTS(SELECT 1 FROM public."PersoneRete" WHERE CASE WHEN trim("CodicePaghe") ~ '^[0-9]+$' THEN trim("CodicePaghe")::numeric END=candidate);
 END LOOP;
 RETURN candidate::text;
END; $$;
REVOKE ALL ON FUNCTION public.amministrativo_genera_codice_paghe() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.amministrativo_genera_codice_paghe() TO authenticated;
CREATE OR REPLACE FUNCTION public.amministrativo_assegna_codice_paghe() RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
 IF NEW."CodicePaghe"='__AUTO_NEXUS__' THEN NEW."CodicePaghe":=public.amministrativo_genera_codice_paghe(); END IF;
 RETURN NEW;
END; $$;
COMMIT;