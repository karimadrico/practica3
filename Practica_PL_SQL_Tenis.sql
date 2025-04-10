/* 2025_v1 */

-- Eliminar tablas y secuencias si existen
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE reservas CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE pistas CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP SEQUENCE seq_pistas';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

-- Crear tablas y secuencia
CREATE TABLE pistas (
    nro INTEGER PRIMARY KEY
);

CREATE TABLE reservas (
    pista INTEGER REFERENCES pistas(nro),
    fecha DATE,
    hora INTEGER CHECK (hora >= 0 AND hora <= 23),
    socio VARCHAR(20),
    PRIMARY KEY (pista, fecha, hora)
);

CREATE SEQUENCE seq_pistas;

-- Insertar datos de ejemplo
INSERT INTO pistas VALUES (seq_pistas.nextval);
INSERT INTO reservas VALUES (1, DATE '2018-03-20', 14, 'Pepito');

INSERT INTO pistas VALUES (seq_pistas.nextval);
INSERT INTO reservas VALUES (2, DATE '2018-03-24', 18, 'Pepito');
INSERT INTO reservas VALUES (2, DATE '2018-03-21', 14, 'Juan');

INSERT INTO pistas VALUES (seq_pistas.nextval);
INSERT INTO reservas VALUES (3, DATE '2018-03-22', 13, 'Lola');
INSERT INTO reservas VALUES (3, DATE '2018-03-22', 12, 'Pepito');

COMMIT;

-- Eliminar funciones obsoletas
BEGIN
    EXECUTE IMMEDIATE 'DROP FUNCTION anularReserva';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP FUNCTION reservarPista';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

-- Procedimiento corregido para reservar pista
CREATE OR REPLACE PROCEDURE pReservarPista(
    p_socio VARCHAR2,
    p_fecha DATE,
    p_hora INTEGER
) AS
    v_pista INTEGER;
BEGIN
    -- Buscar una pista libre sin subconsultas complicadas
    SELECT nro INTO v_pista
    FROM Pistas
    WHERE nro NOT IN (
        SELECT pista
        FROM Reservas
        WHERE trunc(fecha) = trunc(p_fecha)
          AND hora = p_hora
    )
    AND ROWNUM = 1
    FOR UPDATE SKIP LOCKED; -- Bloquear la pista para evitar concurrencia

    -- Si encuentra una pista, hacer la reserva
    INSERT INTO Reservas (pista, fecha, hora, socio) 
    VALUES (v_pista, trunc(p_fecha), p_hora, p_socio);

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Reserva realizada en la pista ' || v_pista);
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('No hay pistas disponibles para esa fecha y hora.');
END;
/



-- Crear procedimiento para anular reserva
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
        DBMS_OUTPUT.PUT_LINE('No se encontró la reserva.');
    ELSE
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Reserva anulada correctamente.');
    END IF;
END;
/


-- Crear procedimiento de prueba para validar las funciones
CREATE OR REPLACE PROCEDURE TEST_FUNCIONES_TENIS AS
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

    DBMS_OUTPUT.PUT_LINE('Pruebas ejecutadas.');
END;
/


-- Ejecutar el procedimiento de prueba
EXEC TEST_FUNCIONES_TENIS;

/*
SET SERVEROUTPUT ON
declare
 resultado integer;
begin
     resultado := reservarPista( 'Socio 1', CURRENT_DATE, 12 );
     if resultado=1 then
        dbms_output.put_line('Reserva 1: OK');
     else
        dbms_output.put_line('Reserva 1: MAL');
     end if;
     
     --Continua tu solo....
     
    resultado := anularreserva( 'Socio 1', CURRENT_DATE, 12, 1);
     if resultado=1 then
        dbms_output.put_line('Reserva 1 anulada: OK');
     else
        dbms_output.put_line('Reserva 1 anulada: MAL');
     end if;
  
     resultado := anularreserva( 'Socio 1', date '1920-1-1', 12, 1);
     --Continua tu solo....
  
end;
/
*/
