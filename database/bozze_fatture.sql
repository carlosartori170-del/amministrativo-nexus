-- Solo bozze amministrative. Non modifica colli, tariffe o bilancini.
CREATE TABLE IF NOT EXISTS public."AmministrativoBozzeFatture" (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 mese text NOT NULL CHECK(mese ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
 pdv integer NOT NULL, contenuto jsonb NOT NULL,
 aggiornato_il timestamptz NOT NULL DEFAULT now(), UNIQUE(mese,pdv)
);
ALTER TABLE public."AmministrativoBozzeFatture" ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public."AmministrativoBozzeFatture" FROM anon, authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON public."AmministrativoBozzeFatture" TO authenticated;
DROP POLICY IF EXISTS nexus_bozze_admin ON public."AmministrativoBozzeFatture";
CREATE POLICY nexus_bozze_admin ON public."AmministrativoBozzeFatture" FOR ALL TO authenticated
USING(EXISTS(SELECT 1 FROM public."NexusProfili" p WHERE p."UserID"=(select auth.uid()) AND p."Attivo" AND p."Ruolo" IN ('admin','amministrazione')))
WITH CHECK(EXISTS(SELECT 1 FROM public."NexusProfili" p WHERE p."UserID"=(select auth.uid()) AND p."Attivo" AND p."Ruolo" IN ('admin','amministrazione')));
DROP POLICY IF EXISTS nexus_tariffe_colli_rete_select_amministrazione ON public."TariffeColliRete";
CREATE POLICY nexus_tariffe_colli_rete_select_amministrazione ON public."TariffeColliRete" FOR SELECT TO authenticated
USING(EXISTS(SELECT 1 FROM public."NexusProfili" p WHERE p."UserID"=(select auth.uid()) AND p."Attivo" AND p."Ruolo"='amministrazione'));
