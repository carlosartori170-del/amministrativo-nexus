-- PROPOSTA. Verificare prima get_project: eqtyfnluswalfassmlxd.
-- Rollback completo SENZA perdita dati: disabilita tutte le nuove API.
-- Ripristinare poi le due app alle versioni pre-intervento.
BEGIN;
REVOKE ALL ON public."WelfareAnnualeDipendenti",public."WelfareAnnualeRiepilogo",
 public."PdrCameriMoltiplicatori",public."PdrCameriMesi",public."PdrCameriVoiceMese",
 public."PdrCameriEccezioni",public."PdrCameriRisultati",public."PdrCameriAudit"
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.nexus_pdr_anteprima(date),public.nexus_pdr_operazione(text,jsonb)
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA nexus_pdr_internal FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON SCHEMA nexus_pdr_internal FROM PUBLIC,anon,authenticated,service_role;
NOTIFY pgrst,'reload schema';
COMMIT;

-- Se il rilascio viene ritirato PRIMA di inserire qualsiasi dato operativo,
-- e' possibile eseguire separatamente anche questo rollback strutturale.
-- In presenza di dati il blocco abortisce: conservare schede, audit, importi pagati.
BEGIN;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM public."WelfareAnnualeDipendenti")
 OR EXISTS(SELECT 1 FROM public."PdrCameriRisultati")
 OR EXISTS(SELECT 1 FROM public."PdrCameriAudit")
 OR EXISTS(SELECT 1 FROM public."PdrCameriMesi" WHERE stato<>'da_classificare')
 THEN RAISE EXCEPTION 'Dati presenti: effettuato solo rollback accessi; non cancellare lo storico'; END IF;
END $$;
DROP VIEW public."WelfareAnnualeRiepilogo";
DROP FUNCTION public.nexus_pdr_anteprima(date);
DROP FUNCTION public.nexus_pdr_operazione(text,jsonb);
DROP TABLE public."PdrCameriRisultati",public."PdrCameriEccezioni",public."PdrCameriVoiceMese";
DROP TABLE public."PdrCameriMesi",public."WelfareAnnualeDipendenti",public."PdrCameriMoltiplicatori",public."PdrCameriAudit";
DROP SCHEMA nexus_pdr_internal CASCADE;
NOTIFY pgrst,'reload schema';
COMMIT;
