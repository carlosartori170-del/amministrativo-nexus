-- Configurazione PDR autorizzata da Carlo: 23093 -> 1806; 23233 -> 1810.
-- Non modifica Dipendenti, ore, colli o stato dei mesi.
BEGIN;
DO $$
DECLARE u uuid;
BEGIN
 SELECT "UserID" INTO STRICT u FROM public."NexusProfili"
 WHERE "Email"='carlo.sartori@nexus-srl.it' AND "Attivo" AND "Ruolo"='admin';
 PERFORM set_config('request.jwt.claim.sub',u::text,true);
 IF NOT EXISTS(SELECT 1 FROM public."Dipendenti" WHERE "ID_Dipendente"=1806 AND "CodiceVoice"=23093 AND "Attivo" AND 2=ANY("Magazzini"))
 OR NOT EXISTS(SELECT 1 FROM public."Dipendenti" WHERE "ID_Dipendente"=1810 AND "CodiceVoice"=23233 AND "Attivo" AND 2=ANY("Magazzini"))
 THEN RAISE EXCEPTION 'Associazioni attive diverse da quelle autorizzate'; END IF;
 INSERT INTO public."PdrCameriVoiceMese"(mese,codice_voice,dipendente_id,motivazione,aggiornato_da)
 SELECT m.mese,v.voice,v.dip,'Autorizzazione Carlo: attribuire il Voice alla anagrafica attiva; storico conservato',u
 FROM public."PdrCameriMesi" m CROSS JOIN(VALUES(23093,1806),(23233,1810))v(voice,dip)
 WHERE m.stato='da_classificare';
END $$;
COMMIT;
