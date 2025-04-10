SELECT * FROM PISTAS;
SELECT * FROM RESERVAS;

EXEC pReservarPista('Socio 5', SYSDATE, 12);

SELECT * FROM RESERVAS;

EXEC pAnularReserva('Socio 5', SYSDATE, 12, 1);

SELECT * FROM RESERVAS;



DECLARE
    v_result INTEGER;
BEGIN
    -- Hacer reservas
    pReservarPista('Socio 1', SYSDATE, 12);
    pReservarPista('Socio 2', SYSDATE, 12);
    pReservarPista('Socio 3', SYSDATE, 12);
    
    -- Intentar una reserva sin éxito
    pReservarPista('Socio 4', SYSDATE, 12);

    -- Cancelar una reserva válida
    pAnularReserva('Socio 1', SYSDATE, 12, 1);
    
    -- Intentar cancelar una reserva inexistente
    pAnularReserva('Socio 1', DATE '1920-01-01', 12, 1);

    -- Mensaje final
    DBMS_OUTPUT.PUT_LINE('Operaciones terminadas, revisa los datos.');
END;
/

SELECT * FROM RESERVAS;

--
--¿Por qué se usa TRUNC(fecha) en las comparaciones?

--TRUNC(fecha) elimina la parte horaria (HH:MI:SS) de un DATE, permitiendo comparar solo la fecha.
--Sin TRUNC, SYSDATE = '06/03/25' podría no coincidir porque tiene horas/minutos/segundos diferentes.

--¿Qué es SQL%ROWCOUNT y cómo funciona?

--Es una variable especial que almacena el número de filas afectadas por la última sentencia INSERT, UPDATE o DELETE. Eemplo:
--DELETE FROM Reservas WHERE socio = 'Juan';
--IF SQL%ROWCOUNT > 0 THEN
--    DBMS_OUTPUT.PUT_LINE('Reserva eliminada.');
--END IF;


--Qué es un cursor en PL/SQL?

--Un cursor almacena el resultado de una consulta SQL para recorrerlo fila por fila.
--En reservarPista hay un cursor vPistasLibres que busca pistas disponibles.
--Operaciones de cursor:
--OPEN cursor; → Ejecuta la consulta.
--FETCH cursor INTO variable; → Toma la siguiente fila.
--CLOSE cursor; → Libera la memoria.
--Propiedades del cursor:
--FOUND = TRUE si hay más filas.
--NOTFOUND = TRUE si no hay más filas.

--¿Se puede cambiar ROLLBACK por COMMIT en anularReserva?

--No se debe cambiar porque si DELETE no afecta ninguna fila, significa que la reserva no existe y no debe confirmarse nada.
-- ¿Puede reservarPista dejar una transacción abierta?

--Sí, si el cursor no se cierra correctamente o falta COMMIT.
--Solución: Siempre cerrar el cursor y usar COMMIT después del INSERT.

--