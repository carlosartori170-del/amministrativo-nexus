BEGIN;
CREATE TABLE public."AmministrativoAnomalieImport" (
 chiave text PRIMARY KEY,tipo text NOT NULL CHECK(tipo IN ('ricevute_pdf','ricevute_excel','emesse_pdf','emesse_excel')),
 origine text NOT NULL,nome_file text NOT NULL,data_documento date,mese text CHECK(mese ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
 messaggio text NOT NULL,creato_il timestamptz NOT NULL DEFAULT now(),aggiornato_il timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public."AmministrativoAnomalieImport" ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public."AmministrativoAnomalieImport" FROM PUBLIC,anon;
GRANT SELECT,INSERT,UPDATE,DELETE ON public."AmministrativoAnomalieImport" TO authenticated;
CREATE POLICY amm_anomalie_import_admin ON public."AmministrativoAnomalieImport" FOR ALL TO authenticated
USING(EXISTS(SELECT 1 FROM public."NexusProfili" p WHERE p."UserID"=(SELECT auth.uid()) AND p."Attivo" AND p."Ruolo" IN ('admin','amministrazione')))
WITH CHECK(EXISTS(SELECT 1 FROM public."NexusProfili" p WHERE p."UserID"=(SELECT auth.uid()) AND p."Attivo" AND p."Ruolo" IN ('admin','amministrazione')));
COMMIT;
