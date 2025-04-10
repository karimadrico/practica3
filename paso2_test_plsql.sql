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
    DBMS_OUTPUT.PUT_LINE('Pruebas completadas. Verifica los datos con SELECT.');
END;
/

-- Verificar los datos después de las pruebas
SELECT * FROM RESERVAS;
