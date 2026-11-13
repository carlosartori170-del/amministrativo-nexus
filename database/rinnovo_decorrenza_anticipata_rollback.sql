-- Prima ripristinare index.html al commit aac232487b697c28e1c40acc613d2e25c40a51f5 (o rimuovere l’uso della RPC anticipata).
-- Non annulla rinnovi registrati dagli utenti: conserva lo storico e i contatori.
DROP FUNCTION IF EXISTS public.amministrativo_rinnova_contratto_anticipato(text,uuid,date,date,text,boolean);
NOTIFY pgrst, 'reload schema';
