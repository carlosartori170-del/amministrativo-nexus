BEGIN;
ALTER TABLE public."AmministrativoFattureEmesse" ADD COLUMN IF NOT EXISTS dati_excel jsonb;
ALTER TABLE public."AmministrativoFattureEmesse" ADD COLUMN IF NOT EXISTS dati_pdf jsonb;
UPDATE public."AmministrativoFattureEmesse" f SET dati_pdf=jsonb_build_object('numero',numero,'data_documento',data_documento,'cliente',cliente,'partita_iva',partita_iva,'imponibile',imponibile,'totale_documento',totale_documento)
WHERE dati_pdf IS NULL AND EXISTS(SELECT 1 FROM public."AmministrativoPdfEmessi" p WHERE p.fattura_id=f.id);
CREATE TABLE IF NOT EXISTS public."AmministrativoPdfEmessiInAttesa" (
 chiave text PRIMARY KEY,nome_file text NOT NULL,cliente text NOT NULL,data_documento date NOT NULL,
 dati_pdf jsonb NOT NULL,contenuto_base64 text NOT NULL,creato_il timestamptz NOT NULL DEFAULT now(),aggiornato_il timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public."AmministrativoPdfEmessiInAttesa" ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public."AmministrativoPdfEmessiInAttesa" FROM anon;
GRANT SELECT,INSERT,UPDATE,DELETE ON public."AmministrativoPdfEmessiInAttesa" TO authenticated;
CREATE POLICY amm_emesse_attesa_admin ON public."AmministrativoPdfEmessiInAttesa" FOR ALL TO authenticated
USING(EXISTS(SELECT 1 FROM public."NexusProfili" p WHERE p."UserID"=(SELECT auth.uid()) AND p."Attivo" AND p."Ruolo" IN ('admin','amministrazione')))
WITH CHECK(EXISTS(SELECT 1 FROM public."NexusProfili" p WHERE p."UserID"=(SELECT auth.uid()) AND p."Attivo" AND p."Ruolo" IN ('admin','amministrazione')));
-- The administrative backup excludes PDF bytes, including the new staging table.
DO $$ DECLARE definition text; BEGIN
 SELECT pg_get_functiondef(p.oid) INTO STRICT definition FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='nexus_backup_internal' AND p.proname='export_application';
 IF position('''AmministrativoPdfEmessiInAttesa''' IN definition)=0 THEN
  IF position('''AmministrativoPdf'',''AmministrativoPdfEmessi'',''AmministrativoPdfInAttesa''' IN definition)=0 THEN RAISE EXCEPTION 'Backup exclusion list has changed'; END IF;
  EXECUTE replace(definition,'''AmministrativoPdf'',''AmministrativoPdfEmessi'',''AmministrativoPdfInAttesa''','''AmministrativoPdf'',''AmministrativoPdfEmessi'',''AmministrativoPdfInAttesa'',''AmministrativoPdfEmessiInAttesa''');
 END IF;
END $$;
CREATE OR REPLACE FUNCTION public.nexus_abbina_pdf_emesso(p_chiave text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE p public."AmministrativoPdfEmessiInAttesa"; f public."AmministrativoFattureEmesse";
BEGIN
 SELECT * INTO p FROM public."AmministrativoPdfEmessiInAttesa" WHERE chiave=p_chiave FOR UPDATE;
 IF p.chiave IS NULL THEN RAISE EXCEPTION 'PDF in attesa non trovato. Ricarica i dati.'; END IF;
 SELECT * INTO f FROM public."AmministrativoFattureEmesse" WHERE chiave=p_chiave FOR UPDATE;
 IF f.id IS NULL OR f.dati_excel IS NULL THEN RAISE EXCEPTION 'Importa prima la riga Excel corrispondente.'; END IF;
 UPDATE public."AmministrativoFattureEmesse" SET dati_pdf=p.dati_pdf,fonte='PDF + Excel',
 imponibile=coalesce(f.imponibile,(p.dati_pdf->>'imponibile')::numeric),
 dettaglio=CASE WHEN coalesce(jsonb_array_length(f.dettaglio),0)=0 THEN p.dati_pdf->'dettaglio' ELSE f.dettaglio END,
 modalita_pagamento=coalesce(nullif(f.modalita_pagamento,''),p.dati_pdf->>'modalita_pagamento'),
 scadenza_pagamento=coalesce(f.scadenza_pagamento,(p.dati_pdf->>'scadenza_pagamento')::date),aggiornato_il=now() WHERE id=f.id;
 INSERT INTO public."AmministrativoPdfEmessi"(fattura_id,nome_file,contenuto_base64) VALUES(f.id,p.nome_file,p.contenuto_base64)
 ON CONFLICT(fattura_id) DO UPDATE SET nome_file=excluded.nome_file,contenuto_base64=excluded.contenuto_base64;
 DELETE FROM public."AmministrativoPdfEmessiInAttesa" WHERE chiave=p_chiave;
END; $$;
REVOKE ALL ON FUNCTION public.nexus_abbina_pdf_emesso(text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.nexus_abbina_pdf_emesso(text) TO authenticated;

COMMIT;
