-- Eliminación de las tablas, secuencias y restricciones
drop table hospital cascade constraints;
drop table tipo_sangre cascade constraints;
drop table reserva_hospital cascade constraints;
drop table donante cascade constraints;
drop table donacion cascade constraints;
drop table traspaso cascade constraints;

drop sequence seq_hospital;
drop sequence seq_tipo_sangre;
drop sequence seq_donacion;
drop sequence seq_traspaso;

-- Creación de la secuencia y tablas

create sequence seq_hospital;
create table hospital (
    id_hospital   integer,
    nombre        varchar(100) not null,
    localidad     varchar(100) not null,
    constraint hospital_pk primary key (id_hospital)
);

create sequence seq_tipo_sangre;
create table tipo_sangre (
    id_tipo_sangre integer,
    descripcion    varchar(10) not null,
    constraint tipo_sangre_pk primary key (id_tipo_sangre)
);

create table reserva_hospital (
    id_tipo_sangre integer,
    id_hospital    integer,
    cantidad       float not null,
    constraint reserva_sangre_pk primary key (id_tipo_sangre, id_hospital),
    constraint reserva_tipo_sangre_fk foreign key (id_tipo_sangre) references tipo_sangre(id_tipo_sangre),
    constraint reserva_hospital_fk foreign key (id_hospital) references hospital(id_hospital),
    constraint reserva_cantidad_reserva_check check (cantidad >= 0)
);

create table donante (
    NIF             varchar(9),
    nombre          varchar(20) not null,
    ape1            varchar(20) not null,
    ape2            varchar(20) not null,
    fecha_nacimiento date not null,  
    id_tipo_sangre  integer not null,
    constraint donante_pk primary key (NIF),
    constraint donante_tipo_sangre_fk foreign key (id_tipo_sangre) references tipo_sangre(id_tipo_sangre)
);

create sequence seq_donacion;
create table donacion (
    id_donacion    integer,
    nif_donante    varchar(20) not null,
    cantidad       float not null,
    fecha_donacion date not null,
    constraint donacion_pk primary key (id_donacion),
    constraint donacion_nif_donante_fk foreign key (nif_donante) references donante(NIF),
    constraint donacion_cantidad_min_check check (cantidad >= 0), 
    constraint donacion_cantidad_max_check check(cantidad <= 0.45)
);

create sequence seq_traspaso;
create table traspaso (
    id_traspaso       integer,
    id_tipo_sangre    integer not null,
    id_hospital_origen integer not null,
    id_hospital_destino integer not null,
    cantidad          float not null,
    fecha_traspaso    date not null,
    constraint traspaso_pk primary key (id_traspaso),
    constraint traspaso_reserva_origen_fk foreign key (id_tipo_sangre, id_hospital_origen) references reserva_hospital(id_tipo_sangre, id_hospital),
    constraint traspaso_reserva_destino_fk foreign key (id_tipo_sangre, id_hospital_destino) references reserva_hospital (id_tipo_sangre, id_hospital),
    constraint traspaso_cantidad_check check (cantidad >= 0)
);

-- Procedimiento realizarTraspaso
CREATE OR REPLACE PROCEDURE realizarTraspaso (
    m_hospital_origen     IN hospital.id_hospital%TYPE,
    m_hospital_destino    IN hospital.id_hospital%TYPE,
    m_tipo_sangre         IN tipo_sangre.id_tipo_sangre%TYPE,
    m_cantidad            IN reserva_hospital.cantidad%TYPE
) IS
    v_existe NUMBER;
    v_cantidad_origen reserva_hospital.cantidad%TYPE;
BEGIN
    -- Validaciones de existencia
    SELECT COUNT(*) INTO v_existe FROM hospital WHERE id_hospital = m_hospital_origen;
    IF v_existe = 0 THEN
        RAISE_APPLICATION_ERROR(-20003, 'Hospital Inexistente');
    END IF;

    SELECT COUNT(*) INTO v_existe FROM hospital WHERE id_hospital = m_hospital_destino;
    IF v_existe = 0 THEN
        RAISE_APPLICATION_ERROR(-20003, 'Hospital Inexistente');
    END IF;

    SELECT COUNT(*) INTO v_existe FROM tipo_sangre WHERE id_tipo_sangre = m_tipo_sangre;
    IF v_existe = 0 THEN
        RAISE_APPLICATION_ERROR(-20002, 'Tipo Sangre Inexistente');
    END IF;

    IF m_cantidad <= 0 THEN
        RAISE_APPLICATION_ERROR(-20007, 'Valor de cantidad de traspaso por debajo de lo requerido');
    END IF;

    -- Verificar reserva suficiente en origen
    BEGIN
        SELECT cantidad INTO v_cantidad_origen FROM reserva_hospital 
        WHERE id_hospital = m_hospital_origen AND id_tipo_sangre = m_tipo_sangre;
        IF v_cantidad_origen < m_cantidad THEN
            RAISE_APPLICATION_ERROR(-20004, 'Valor de reserva por debajo de lo requerido');
        END IF;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20004, 'Valor de reserva por debajo de lo requerido');
    END;

    -- Insertar o actualizar reservas
    MERGE INTO reserva_hospital r
    USING (SELECT m_hospital_destino AS id_hospital, m_tipo_sangre AS id_tipo_sangre FROM dual) src
    ON (r.id_hospital = src.id_hospital AND r.id_tipo_sangre = src.id_tipo_sangre)
    WHEN MATCHED THEN
        UPDATE SET cantidad = cantidad + m_cantidad
    WHEN NOT MATCHED THEN
        INSERT (id_hospital, id_tipo_sangre, cantidad) VALUES (m_hospital_destino, m_tipo_sangre, m_cantidad);

    -- Actualizar reserva origen
    UPDATE reserva_hospital 
    SET cantidad = cantidad - m_cantidad
    WHERE id_hospital = m_hospital_origen AND id_tipo_sangre = m_tipo_sangre;

    -- Registrar el traspaso
    INSERT INTO traspaso (id_traspaso, id_tipo_sangre, id_hospital_origen, id_hospital_destino, cantidad, fecha_traspaso)
    VALUES (seq_traspaso.NEXTVAL, m_tipo_sangre, m_hospital_origen, m_hospital_destino, m_cantidad, SYSDATE);

    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END;
/

--Procedimiento realizar donacion
CREATE OR REPLACE PROCEDURE realizarDonacion (
    m_NIF_donante IN donante.NIF%TYPE,
    m_cantidad IN donacion.cantidad%TYPE,
    m_hospital IN hospital.id_hospital%TYPE
)
IS
    v_fecha_ultima_donacion DATE;
    v_count INTEGER;  -- Declaración de la variable 'v_count'
BEGIN
    -- Comprobar si el donante existe
    SELECT COUNT(*) INTO v_count FROM donante WHERE NIF = m_NIF_donante;
    IF v_count = 0 THEN
        RAISE_APPLICATION_ERROR(-20001, 'Donante Inexistente');
    END IF;

    -- Validar la cantidad de donación
    IF m_cantidad < 0 OR m_cantidad > 0.45 THEN
        RAISE_APPLICATION_ERROR(-20005, 'Valor de cantidad de donación incorrecto');
    END IF;

    -- Verificar si el donante ha donado recientemente
    SELECT MAX(fecha_donacion) INTO v_fecha_ultima_donacion
    FROM donacion
    WHERE nif_donante = m_NIF_donante;

    IF v_fecha_ultima_donacion IS NOT NULL AND v_fecha_ultima_donacion > (SYSDATE - 15) THEN
        RAISE_APPLICATION_ERROR(-20006, 'Donante excede el cupo de donación');
    END IF;

    -- Insertar la donación en la tabla de donaciones
    INSERT INTO donacion (id_donacion, nif_donante, cantidad, fecha_donacion)
    VALUES (SEQ_DONACION.NEXTVAL, m_NIF_donante, m_cantidad, SYSDATE);

    -- Actualizar la reserva del hospital
    UPDATE reserva_hospital
    SET cantidad = cantidad + m_cantidad
    WHERE id_hospital = m_hospital AND id_tipo_sangre = (SELECT id_tipo_sangre FROM donante WHERE NIF = m_NIF_donante);

    COMMIT;
END;





-- Procedimiento reset_seq
create or replace procedure reset_seq( p_seq_name varchar ) is
    l_val number;
begin
    -- Averiguo cual es el siguiente valor y lo guardo en l_val
    execute immediate
    'select ' || p_seq_name || '.nextval from dual' INTO l_val;

    -- Utilizo ese valor en negativo para poner la secuencia a cero
    execute immediate
    'alter sequence ' || p_seq_name || ' increment by -' || l_val || ' minvalue 0';
    
    -- Segundo pidiendo el siguiente valor
    execute immediate
    'select ' || p_seq_name || '.nextval from dual' INTO l_val;

    -- Restauro el incremento de la secuencia a 1
    execute immediate
    'alter sequence ' || p_seq_name || ' increment by 1 minvalue 0';
end;
/

-- Procedimiento inicializa_test
CREATE OR REPLACE PROCEDURE inicializa_test IS
    -- Definición de las constantes para los tipos de sangre
    sangre_a CONSTANT NUMBER := 1;
    sangre_b CONSTANT NUMBER := 2;
    sangre_o CONSTANT NUMBER := 3;
    sangre_ab CONSTANT NUMBER := 4;
BEGIN
    DBMS_OUTPUT.PUT_LINE('Iniciando inicializa_test...');

    -- Primero, insertar los hospitales
    INSERT INTO hospital (id_hospital, nombre, localidad) 
    VALUES (seq_hospital.nextval, 'Complejo Asistencial de Avila', 'Avila');
    INSERT INTO hospital (id_hospital, nombre, localidad) 
    VALUES (seq_hospital.nextval, 'Hospital Santos Reyes de Aranda de Duero', 'Aranda Duero');
    INSERT INTO hospital (id_hospital, nombre, localidad) 
    VALUES (seq_hospital.nextval, 'Complejo Asistencial Univesitario de Leon', 'Leon');
    INSERT INTO hospital (id_hospital, nombre, localidad) 
    VALUES (seq_hospital.nextval, 'Complejo Asistencial Universitario de Palencia', 'Palencia');

    -- Los registros de reserva de hospitales (sangre_a, sangre_b, etc.)
    INSERT INTO reserva_hospital (id_tipo_sangre, id_hospital, cantidad) 
    VALUES (sangre_a, seq_hospital.currval, 3.45);   -- Uso de ID real
    INSERT INTO reserva_hospital (id_tipo_sangre, id_hospital, cantidad) 
    VALUES (sangre_b, seq_hospital.currval, 2.5);    -- Uso de ID real
    INSERT INTO reserva_hospital (id_tipo_sangre, id_hospital, cantidad) 
    VALUES (sangre_o, seq_hospital.currval, 10.2);   -- Uso de ID real
    INSERT INTO reserva_hospital (id_tipo_sangre, id_hospital, cantidad) 
    VALUES (sangre_ab, seq_hospital.currval, 5.3);    -- Uso de ID real

    -- Los traspasos
    INSERT INTO traspaso (id_traspaso, id_tipo_sangre, id_hospital_origen, id_hospital_destino, cantidad, fecha_traspaso)
    VALUES (seq_traspaso.nextval, 1, 1, 2, 20, TO_DATE('11/01/2025', 'DD/MM/YYYY'));  
    INSERT INTO traspaso (id_traspaso, id_tipo_sangre, id_hospital_origen, id_hospital_destino, cantidad, fecha_traspaso)
    VALUES (seq_traspaso.nextval, 2, 2, 1, 30, TO_DATE('11/01/2025', 'DD/MM/YYYY'));  
    INSERT INTO traspaso (id_traspaso, id_tipo_sangre, id_hospital_origen, id_hospital_destino, cantidad, fecha_traspaso)
    VALUES (seq_traspaso.nextval, 3, 3, 2, 10, TO_DATE('11/01/2025', 'DD/MM/YYYY'));  
    INSERT INTO traspaso (id_traspaso, id_tipo_sangre, id_hospital_origen, id_hospital_destino, cantidad, fecha_traspaso)
    VALUES (seq_traspaso.nextval, 4, 4, 3, 15, TO_DATE('11/01/2025', 'DD/MM/YYYY'));  

    -- Inserciones de los donantes
    INSERT INTO donante (nif, nombre, ape1, ape2, fecha_nacimiento, id_tipo_sangre, segundo_apellido) 
    VALUES ('12345678A', 'Juan', 'Pérez', 'González', TO_DATE('1990/01/01', 'YYYY/MM/DD'), 1, 'Martínez');
    INSERT INTO donante (nif, nombre, ape1, ape2, fecha_nacimiento, id_tipo_sangre, segundo_apellido) 
    VALUES ('23456789B', 'Ana', 'Gómez', 'López', TO_DATE('1985/06/15', 'YYYY/MM/DD'), 2, 'Fernández');
    INSERT INTO donante (nif, nombre, ape1, ape2, fecha_nacimiento, id_tipo_sangre, segundo_apellido) 
    VALUES ('34567890C', 'Luis', 'Morales', 'Díaz', TO_DATE('1982/11/20', 'YYYY/MM/DD'), 3, 'Pérez');

    DBMS_OUTPUT.PUT_LINE('Datos inicializados correctamente.');
END;
/




-- Procedimiento test_donaciones
CREATE OR REPLACE PROCEDURE test_donaciones IS
BEGIN
  DBMS_OUTPUT.PUT_LINE('Iniciando test_donaciones...');

  -- Prueba de hospital inexistente
  BEGIN
    -- Aquí se supone que '999' es un hospital que no existe
    realizarTraspaso(999, 1, 1, 1);  
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Excepción esperada (hospital inexistente): ' || SQLERRM);
  END;

  -- Prueba de donante inexistente
  BEGIN
    -- '99999999X' es un NIF que no existe en la tabla de donantes
    realizarDonacion('99999999X', 0.4, 1);  -- Se agrega el hospital como tercer parámetro
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Excepción esperada (donante inexistente): ' || SQLERRM);
  END;

  -- Prueba de cantidad de donación inválida
  BEGIN
    -- '12345678A' es un NIF válido, pero la cantidad es mayor a 0.45, lo cual es inválido
    realizarDonacion('12345678A', 0.6, 1);  -- Cantidad > 0.45
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Excepción esperada (cantidad de donación inválida): ' || SQLERRM);
  END;

  -- Prueba de donación en menos de 15 días
  BEGIN
    -- Suponiendo que '12345678A' ya ha donado hace menos de 15 días, intentamos otra donación
    realizarDonacion('12345678A', 0.3, 1);  -- Ya donó hace menos de 15 días
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Excepción esperada (donación en menos de 15 días): ' || SQLERRM);
  END;

  -- Prueba de traspaso válido
  BEGIN
    -- Se realiza un traspaso correcto entre los hospitales 1 y 2, con el tipo de sangre 1 y 0.3 litros
    realizarTraspaso(1, 2, 1, 0.3);
    DBMS_OUTPUT.PUT_LINE('Traspaso realizado correctamente');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Excepción inesperada (traspaso válido): ' || SQLERRM);
  END;

END;
/




-- Primero

begin
   inicializa_test;
end;

-- Despues 

set serveroutput on;

-- Finalmente
begin
  test_donaciones;
end;

-- Donación válida
EXEC realizarDonacion('12345678A', 0.3, 1);

-- Donante inexistente
EXEC realizarDonacion('00000000Z', 0.3, 1);
-- Esperado: Donante Inexistente (-20001)

-- Hospital inexistente
EXEC realizarDonacion('12345678A', 0.3, 999);
-- Esperado: Hospital Inexistente (-20003)

-- Cantidad inválida
EXEC realizarDonacion('12345678A', 0.6, 1);
-- Esperado: Valor de cantidad incorrecto (-20005)

-- Donación < 15 días
EXEC realizarDonacion('12345678A', 0.3, 1);
-- Esperado: Donante excede el cupo (-20006)





