DROP FUNCTION reservarPista;
DROP FUNCTION anularReserva;

CREATE OR REPLACE PROCEDURE pReservarPista(
    p_socio VARCHAR2,
    p_fecha DATE,
    p_hora INTEGER
) AS
    v_pista INTEGER;
BEGIN
    SELECT nro INTO v_pista FROM Pistas
    WHERE nro NOT IN (
        SELECT pista FROM Reservas 
        WHERE trunc(fecha) = trunc(p_fecha) 
          AND hora = p_hora
    ) AND ROWNUM = 1;

    INSERT INTO Reservas (pista, fecha, hora, socio) 
    VALUES (v_pista, trunc(p_fecha), p_hora, p_socio);

    COMMIT;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20001, 'No quedan pistas libres en esa fecha y hora.');
END;
/

CREATE OR REPLACE PROCEDURE pAnularReserva(
    p_socio VARCHAR2,
    p_fecha DATE,
    p_hora INTEGER,
    p_pista INTEGER
) AS
BEGIN
    DELETE FROM Reservas 
    WHERE Socio = p_socio 
      AND trunc(Fecha) = trunc(p_fecha) 
      AND Hora = p_hora 
      AND Pista = p_pista;

    IF SQL%ROWCOUNT = 0 THEN
        RAISE_APPLICATION_ERROR(-20000, 'Reserva inexistente.');
    END IF;

    COMMIT;
END;
/
