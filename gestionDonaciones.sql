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
    m_cantidad    IN donacion.cantidad%TYPE,
    m_hospital    IN hospital.id_hospital%TYPE
) IS
    v_tipo_sangre donante.id_tipo_sangre%TYPE;
    v_fecha_ultima donacion.fecha_donacion%TYPE;
    v_existe NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_existe FROM donante WHERE NIF = m_NIF_donante;
    IF v_existe = 0 THEN
        RAISE_APPLICATION_ERROR(-20001, 'Donante Inexistente');
    END IF;

    SELECT id_tipo_sangre INTO v_tipo_sangre FROM donante WHERE NIF = m_NIF_donante;

    SELECT COUNT(*) INTO v_existe FROM tipo_sangre WHERE id_tipo_sangre = v_tipo_sangre;
    IF v_existe = 0 THEN
        RAISE_APPLICATION_ERROR(-20002, 'Tipo Sangre Inexistente');
    END IF;

    SELECT COUNT(*) INTO v_existe FROM hospital WHERE id_hospital = m_hospital;
    IF v_existe = 0 THEN
        RAISE_APPLICATION_ERROR(-20003, 'Hospital Inexistente');
    END IF;

    IF m_cantidad <= 0 OR m_cantidad > 0.45 THEN
        RAISE_APPLICATION_ERROR(-20005, 'Valor de cantidad de donación incorrecto');
    END IF;

    BEGIN
        SELECT MAX(fecha_donacion) INTO v_fecha_ultima FROM donacion WHERE nif_donante = m_NIF_donante;
        IF v_fecha_ultima > SYSDATE - 15 THEN
            RAISE_APPLICATION_ERROR(-20006, 'Donante excede el cupo de donación');
        END IF;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN NULL;
    END;

    INSERT INTO donacion (id_donacion, nif_donante, cantidad, fecha_donacion)
    VALUES (seq_donacion.NEXTVAL, m_NIF_donante, m_cantidad, SYSDATE);

    MERGE INTO reserva_hospital r
    USING (SELECT m_hospital AS id_hospital, v_tipo_sangre AS id_tipo_sangre FROM dual) src
    ON (r.id_hospital = src.id_hospital AND r.id_tipo_sangre = src.id_tipo_sangre)
    WHEN MATCHED THEN
        UPDATE SET cantidad = cantidad + m_cantidad
    WHEN NOT MATCHED THEN
        INSERT (id_hospital, id_tipo_sangre, cantidad) VALUES (m_hospital, v_tipo_sangre, m_cantidad);

    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END;
/



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
create or replace procedure inicializa_test is
    sangre_a tipo_sangre.id_tipo_sangre%type;
    sangre_b tipo_sangre.id_tipo_sangre%type;
    sangre_ab tipo_sangre.id_tipo_sangre%type;
    sangre_o tipo_sangre.id_tipo_sangre%type;
begin
    reset_seq( 'seq_tipo_sangre' );
    reset_seq( 'seq_hospital' );
    reset_seq( 'seq_traspaso' );
    reset_seq('seq_donacion');
    
    delete from traspaso;
    delete from reserva_hospital;
    delete from donacion;
    delete from donante;
    delete from tipo_sangre;
    delete from hospital;
    
    
    insert into tipo_sangre values (seq_tipo_sangre.nextval, 'Tipo A');
    sangre_a := seq_tipo_sangre.currval;
    insert into tipo_sangre values (seq_tipo_sangre.nextval, 'Tipo B');
    sangre_b := seq_tipo_sangre.currval;
    insert into tipo_sangre values (seq_tipo_sangre.nextval, 'Tipo AB');
    sangre_ab := seq_tipo_sangre.currval;
    insert into tipo_sangre values (seq_tipo_sangre.nextval, 'Tipo O');
    sangre_o := seq_tipo_sangre.currval;
    
    insert into hospital values (seq_hospital.nextval, 'Complejo Asistencial de Avila', 'Avila');
    insert into reserva_hospital values (sangre_a, seq_hospital.currval, 3.45);
    insert into reserva_hospital values (sangre_b, seq_hospital.currval, 2.5);
    insert into reserva_hospital values (sangre_ab, seq_hospital.currval, 5.82);
    insert into reserva_hospital values (sangre_o, seq_hospital.currval, 2.6);
    
    insert into hospital values (seq_hospital.nextval, 'Hospital Santos Reyes de Aranda de Duero', 'Aranda Duero');
    insert into reserva_hospital values (sangre_a, seq_hospital.currval, 2.45);
    insert into reserva_hospital values (sangre_b, seq_hospital.currval, 1.5);
    insert into reserva_hospital values (sangre_ab, seq_hospital.currval, 0.82);
    
    insert into hospital values (seq_hospital.nextval, 'Complejo Asistencial Univesitario de Leon', 'Leon');
    insert into reserva_hospital values (sangre_a, seq_hospital.currval, 6.52);
    insert into reserva_hospital values (sangre_b, seq_hospital.currval, 5.7);
    insert into reserva_hospital values (sangre_ab, seq_hospital.currval, 10.26);
    insert into reserva_hospital values (sangre_o, seq_hospital.currval, 8.64);
    
    insert into hospital values (seq_hospital.nextval, 'Complejo Asistencial Universitario de Palencia', 'Palencia');
    insert into reserva_hospital values (sangre_ab, seq_hospital.currval, 3.61);
    insert into reserva_hospital values (sangre_o, seq_hospital.currval, 1.91);
    
    insert into donante values ('12345678A', 'Juan', 'Garcia', 'Porras', to_date('24/03/1983', 'DD/MM/YYYY'), sangre_a);
    insert into donante values ('77777777B', 'Lucia', 'Rodriguez', 'Martin', to_date('12/04/1963', 'DD/MM/YYYY'), sangre_a);
    insert into donante values ('98989898C', 'Maria', 'Fernandez', 'Dominguez', to_date('01/12/1977', 'DD/MM/YYYY'), sangre_o);
    insert into donante values ('98765432Y', 'Alba', 'Serrano', 'Garcia', to_date('09/06/1997', 'DD/MM/YYYY'), sangre_ab);
    
    insert into donacion values (seq_donacion.nextval, '12345678A', 0.25, to_date('10/01/2025', 'DD/MM/YYYY') );
    insert into donacion values (seq_donacion.nextval, '12345678A', 0.40, to_date('15/01/2025', 'DD/MM/YYYY') );
    insert into donacion values (seq_donacion.nextval, '77777777B', 0.35, to_date('15/01/2025', 'DD/MM/YYYY') );
    insert into donacion values (seq_donacion.nextval, '98989898C', 0.25, to_date('25/01/2025', 'DD/MM/YYYY') );
    insert into donacion values (seq_donacion.nextval, '98765432Y', 0.35, to_date('25/01/2025', 'DD/MM/YYYY') );
    
    insert into traspaso values (seq_traspaso.nextval, 1, 1, 2, 20, to_date('11/01/2025', 'DD/MM/YYYY') );
    insert into traspaso values (seq_traspaso.nextval, 2, 1, 2, 30, to_date('11/01/2025', 'DD/MM/YYYY') );
    insert into traspaso values (seq_traspaso.nextval, 3, 1, 2, 10, to_date('11/01/2025', 'DD/MM/YYYY') );
    insert into traspaso values (seq_traspaso.nextval, 4, 1, 3, 15, to_date('11/01/2025', 'DD/MM/YYYY') );
end;
/

-- Procedimiento para realizar test de donación
CREATE OR REPLACE PROCEDURE test_donaciones IS
BEGIN
  DBMS_OUTPUT.PUT_LINE('Iniciando test_donaciones...');

  -- Prueba de hospital inexistente
  BEGIN
    realizarTraspaso(999, 1, 1, 1);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Excepción esperada: ' || SQLERRM);
  END;

  -- Prueba de donante inexistente
  BEGIN
    realizarDonacion('99999999X', 0.4, 1);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Excepción esperada: ' || SQLERRM);
  END;

  -- Prueba de cantidad de donación inválida
  BEGIN
    realizarDonacion('12345678A', 0.6, 1);  -- Cantidad > 0.45
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Excepción esperada: ' || SQLERRM);
  END;

  -- Prueba de donación en menos de 15 días
  BEGIN
    realizarDonacion('12345678A', 0.3, 1);  -- Ya donó hace menos de 15 días
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Excepción esperada: ' || SQLERRM);
  END;

  -- Prueba de traspaso válido
  BEGIN
    realizarTraspaso(1, 2, 1, 0.3);
    DBMS_OUTPUT.PUT_LINE('Traspaso realizado correctamente');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Excepción inesperada: ' || SQLERRM);
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


-- Donación válida:
EXEC realizarDonacion('12345678A', 0.3, 1);

-- Donante inexistente:
EXEC realizarDonacion('00000000Z', 0.3, 1);
-- Esperado: Donante Inexistente (-20001)

-- Hospital inexistente:
EXEC realizarDonacion('12345678A', 0.3, 999);
-- Esperado: Hospital Inexistente (-20003)

-- Cantidad inválida:
EXEC realizarDonacion('12345678A', 0.6, 1);
-- Esperado: Valor de cantidad incorrecto (-20005)

-- Donación < 15 días:
EXEC realizarDonacion('12345678A', 0.3, 1);
-- Esperado: Donante excede el cupo (-20006)

-- Traspaso válido:
EXEC realizarTraspaso(1, 2, 1, 0.3);

-- Traspaso con hospital inexistente:
EXEC realizarTraspaso(99, 2, 1, 0.3);
-- Esperado: Hospital Inexistente (-20003)

-- Traspaso con reserva insuficiente:
EXEC realizarTraspaso(1, 2, 1, 100);
-- Esperado: Reserva insuficiente (-20004)




