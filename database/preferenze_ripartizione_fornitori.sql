BEGIN;
ALTER TABLE public."AmministrativoRegoleFornitori" ALTER COLUMN categoria_id DROP NOT NULL;
ALTER TABLE public."AmministrativoRegoleFornitori" ADD COLUMN IF NOT EXISTS durata_mesi integer CHECK (durata_mesi BETWEEN 1 AND 120);
ALTER TABLE public."AmministrativoFatture" ADD COLUMN IF NOT EXISTS ripartizione_verificata boolean NOT NULL DEFAULT false;
CREATE OR REPLACE FUNCTION public.nexus_ricorda_preferenze_fornitore(p_partita_iva text,p_nome text,p_categoria uuid DEFAULT NULL,p_durata integer DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
BEGIN
 IF nullif(btrim(p_partita_iva),'') IS NULL THEN RAISE EXCEPTION 'Partita IVA mancante'; END IF;
 IF p_categoria IS NULL AND p_durata IS NULL THEN RETURN; END IF;
 INSERT INTO public."AmministrativoRegoleFornitori" AS r (partita_iva,nome,categoria_id,durata_mesi,aggiornato_il)
 VALUES(p_partita_iva,p_nome,p_categoria,p_durata,now())
 ON CONFLICT(partita_iva) DO UPDATE SET nome=excluded.nome,
 categoria_id=coalesce(p_categoria,r.categoria_id),durata_mesi=coalesce(p_durata,r.durata_mesi),aggiornato_il=now();
END; $$;
REVOKE ALL ON FUNCTION public.nexus_ricorda_preferenze_fornitore(text,text,uuid,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.nexus_ricorda_preferenze_fornitore(text,text,uuid,integer) TO authenticated;
-- Credit-note edits also retain an explicitly chosen one-month split.
DO $$ DECLARE definition text; BEGIN
 SELECT pg_get_functiondef(p.oid) INTO STRICT definition FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='nexus_salva_nota_credito';
 IF position('SET imponibile=amount,' IN definition)>0 THEN
 EXECUTE replace(definition,'SET imponibile=amount,','SET ripartizione_verificata=true,imponibile=amount,');
 ELSIF position('SET ripartizione_verificata=true,imponibile=amount,' IN definition)=0 THEN RAISE EXCEPTION 'Credit-note function has changed'; END IF;
END; $$;
COMMIT;
