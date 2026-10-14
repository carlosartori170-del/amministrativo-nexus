CREATE TABLE public."AmministrativoCausaliCessazione" (
 nome text PRIMARY KEY CHECK (length(trim(nome)) BETWEEN 1 AND 2000),
 chiave text GENERATED ALWAYS AS (lower(regexp_replace(trim(nome),'\s+',' ','g'))) STORED UNIQUE,
 creato_il timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public."AmministrativoCausaliCessazione" ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public."AmministrativoCausaliCessazione" FROM anon,authenticated;
GRANT SELECT,INSERT ON public."AmministrativoCausaliCessazione" TO authenticated;
CREATE POLICY causali_lettura ON public."AmministrativoCausaliCessazione" FOR SELECT TO authenticated USING (EXISTS(SELECT 1 FROM public."NexusProfili" WHERE "UserID"=(SELECT auth.uid()) AND "Attivo" AND "Ruolo" IN ('admin','amministrazione')));
CREATE POLICY causali_inserimento ON public."AmministrativoCausaliCessazione" FOR INSERT TO authenticated WITH CHECK (EXISTS(SELECT 1 FROM public."NexusProfili" WHERE "UserID"=(SELECT auth.uid()) AND "Attivo" AND "Ruolo" IN ('admin','amministrazione')));
INSERT INTO public."AmministrativoCausaliCessazione"(nome) SELECT DISTINCT trim(causale_cessazione) FROM public."AmministrativoDatiPersonale" WHERE nullif(trim(causale_cessazione),'') IS NOT NULL ON CONFLICT DO NOTHING;
CREATE FUNCTION public.amministrativo_memorizza_causale() RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
 IF nullif(trim(NEW.causale_cessazione),'') IS NOT NULL THEN
 INSERT INTO public."AmministrativoCausaliCessazione"(nome) VALUES(trim(NEW.causale_cessazione)) ON CONFLICT DO NOTHING;
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.amministrativo_memorizza_causale() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER memorizza_causale_cessazione AFTER INSERT OR UPDATE OF causale_cessazione ON public."AmministrativoDatiPersonale" FOR EACH ROW EXECUTE FUNCTION public.amministrativo_memorizza_causale();
