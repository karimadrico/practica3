
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


-- hospital que recibe litros de sangre
create sequence seq_hospital;
create table hospital (
	id_hospital	integer,
	nombre	varchar(100) not null,
	localidad varchar(100) not null,
    constraint hospital_pk primary key (id_hospital)
);

-- tipos de sangre del centro, en el campo reserva está la sangre de la que disponibe el centro ante la petición de hospitales, nunca menor que 0
create sequence seq_tipo_sangre;
create table tipo_sangre (
	id_tipo_sangre	integer,
	descripcion	varchar(10) not null,
    constraint tipo_sangre_pk primary key (id_tipo_sangre)
);


create table reserva_hospital (
    id_tipo_sangre integer,
    id_hospital integer,
    cantidad float not null,
    constraint reserva_sangre_pk primary key (id_tipo_sangre, id_hospital),
    constraint reserva_tipo_sangre_fk foreign key (id_tipo_sangre) references tipo_sangre(id_tipo_sangre),
    constraint reserva_hospital_fk foreign key (id_hospital) references hospital(id_hospital),
    constraint reserva_cantidad_reserva_check  check (cantidad >= 0)
);


-- persona que dona y tiene un tipo de sangre
create table donante (
	NIF	varchar(9) ,
	nombre	varchar(20) not null,
	ape1	varchar(20) not null,
	ape2	varchar(20) not null,
	fecha_nacimiento date not null,	
	id_tipo_sangre integer not null,
    constraint donante_pk primary key (NIF),
    constraint donante_tipo_sangre_fk foreign key (id_tipo_sangre) references tipo_sangre(id_tipo_sangre)
);


-- en esta tabla se guarda cada donación
create sequence seq_donacion;
create table donacion (
	id_donacion	integer,
	nif_donante varchar(20) not null,
	cantidad float not null,
	fecha_donacion date not null,
    constraint donacion_pk primary key (id_donacion),
    constraint donacion_nif_donante_fk foreign key (nif_donante) references donante(NIF),
    constraint donacion_cantidad_min_check check (cantidad >= 0), 
    constraint donacion_cantidad_max_check check(cantidad <= 0.45)
);


-- en esta tabla se guarda cada traspaso de sangre del centro a un hospital
create sequence seq_traspaso;
create table traspaso (
	id_traspaso	integer,
	id_tipo_sangre integer not null,
	id_hospital_origen integer not null,
	id_hospital_destino integer not null,
	cantidad float not null,
	fecha_traspaso date not null,
    constraint traspaso_pk primary key (id_traspaso),
    constraint traspaso_reserva_origen_fk foreign key (id_tipo_sangre,id_hospital_origen) references reserva_hospital(id_tipo_sangre,id_hospital),
    constraint traspaso_reserva_destino_fk foreign key (id_tipo_sangre,id_hospital_destino) references reserva_hospital (id_tipo_sangre,id_hospital),
    constraint traspaso_cantidad_check check (cantidad >= 0)
);



-------------------------------------------------------------------------------------

-- Procedimiento realizarTraspaso
create or replace procedure realizarTraspaso (
    m_hospital_origen hospital.id_hospital%type,
    m_hospital_destino hospital.id_hospital%type,
    m_tipo_sangre tipo_sangre.id_tipo_sangre%type,
    m_cantidad reserva_hospital.cantidad%type
) is
    v_cantidad_origen reserva_hospital.cantidad%type;
    v_cantidad_destino reserva_hospital.cantidad%type;
BEGIN
    -- Comprobar que hay suficiente sangre en el hospital de origen
    select cantidad into v_cantidad_origen
    from reserva_hospital
    where id_hospital = m_hospital_origen
    and id_tipo_sangre = m_tipo_sangre;
    
    -- Comprobar que hay capacidad en el hospital de destino
    select cantidad into v_cantidad_destino
    from reserva_hospital
    where id_hospital = m_hospital_destino
    and id_tipo_sangre = m_tipo_sangre;
    
    -- Verificar que la cantidad en el hospital de origen es suficiente
    if v_cantidad_origen < m_cantidad then
        raise_application_error(-20001, 'No hay suficiente sangre en el hospital de origen');
    end if;
    
    -- Actualizar reservas en el hospital de origen
    update reserva_hospital
    set cantidad = cantidad - m_cantidad
    where id_hospital = m_hospital_origen
    and id_tipo_sangre = m_tipo_sangre;
    
    -- Actualizar reservas en el hospital de destino
    update reserva_hospital
    set cantidad = cantidad + m_cantidad
    where id_hospital = m_hospital_destino
    and id_tipo_sangre = m_tipo_sangre;
    
    -- Registrar el traspaso
    insert into traspaso (id_traspaso, id_tipo_sangre, id_hospital_origen, id_hospital_destino, cantidad, fecha_traspaso)
    values (seq_traspaso.nextval, m_tipo_sangre, m_hospital_origen, m_hospital_destino, m_cantidad, sysdate);
    
    commit;
END;
/

-- Procedimiento realizarDonacion
create or replace procedure realizarDonacion (
    m_NIF_donante donante.NIF%type,
    m_cantidad donacion.cantidad%type,
    m_hospital hospital.id_hospital%type
) is
    v_tipo_sangre donante.id_tipo_sangre%type;
    v_fecha_ultima_donacion DATE;
BEGIN
    -- Verificar que el donante existe
    begin
        select id_tipo_sangre into v_tipo_sangre
        from donante
        where NIF = m_NIF_donante;
    exception
        when no_data_found then
            raise_application_error(-20003, 'El donante con NIF ' || m_NIF_donante || ' no existe.');
    end;
    
    -- Comprobar que la cantidad es válida (entre 0 y 0.45)
    if m_cantidad <= 0 or m_cantidad > 0.45 then
        raise_application_error(-20002, 'La cantidad de la donación no es válida');
    end if;
    
    -- Registrar la donación
    insert into donacion (id_donacion, nif_donante, cantidad, fecha_donacion)
    values (seq_donacion.nextval, m_NIF_donante, m_cantidad, sysdate);
    
    -- Actualizar las reservas del hospital
    update reserva_hospital
    set cantidad = cantidad + m_cantidad
    where id_hospital = m_hospital
    and id_tipo_sangre = v_tipo_sangre;
    
    commit;
END;
/




-------------------------------------------------------------------------------------


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

    -- Restoura el incremento de la secuencia a 1
    execute immediate
    'alter sequence ' || p_seq_name || ' increment by 1 minvalue 0';
end;
/


create or replace procedure inicializa_test is
    sangre_a tipo_sangre.id_tipo_sangre%type;
    sangre_b tipo_sangre.id_tipo_sangre%type;
    sangre_ab tipo_sangre.id_tipo_sangre%type;
    sangre_o tipo_sangre.id_tipo_sangre%type;
begin
    reset_seq( 'seq_tipo_sangre' );
    reset_seq( 'seq_hospital' );
    reset_seq( 'seq_traspaso' );
    reset_seq(' seq_donacion');
    
    
	delete from traspaso;
    delete from reserva_hospital;
	delete from donacion;
	delete from donante;
	delete from tipo_sangre;
	delete from hospital;
    

	insert into tipo_sangre values (seq_tipo_sangre.nextval, 'Tipo A.');
    sangre_a:= seq_tipo_sangre.currval;
	insert into tipo_sangre values (seq_tipo_sangre.nextval, 'Tipo B.');
    sangre_b:= seq_tipo_sangre.currval;
	insert into tipo_sangre values (seq_tipo_sangre.nextval, 'Tipo AB.');
    sangre_ab:= seq_tipo_sangre.currval;
	insert into tipo_sangre values (seq_tipo_sangre.nextval, 'Tipo O.');
    sangre_o:= seq_tipo_sangre.currval;
    
	
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
	insert into traspaso values (seq_traspaso.nextval, 3, 1, 2, 20, to_date('11/01/2025', 'DD/MM/YYYY') );
	insert into traspaso values (seq_traspaso.nextval, 1, 2, 3, 50, to_date('16/01/2025', 'DD/MM/YYYY') );
	insert into traspaso values (seq_traspaso.nextval, 2, 3, 2, 80, to_date('16/01/2025', 'DD/MM/YYYY') );
	
    commit;
end;
/

            
create or replace procedure test_donaciones is
begin

    dbms_output.put_line('COMIENZO TESTS:');
    dbms_output.put_line('----------------------------------------------------');
    
    --Prueba caso DONANTE_INEXISTENTE
    begin
        inicializa_test;
        realizarDonacion ('66666666L', 0.3, 1);
        dbms_output.put_line('KO, no detecta DONANTE_INEXISTENTE');
    exception
        when others then
            if sqlcode = -20001 then
                dbms_output.put_line('OK, detecta DONANTE_INEXISTENTE: '||sqlerrm);
            else
                dbms_output.put_line('KO, no detecta DONANTE_INEXISTENTE: '||sqlerrm);
            end if;
    end;
    
    -- Prueba caso TIPO_SANGRE_INEXISTENTE
    
    -- Prueba caso HOSPITAL_INEXISTENTE
    
    -- Prueba caso RESERVA_INSUFICIENTE
    
    -- Prueba caso CANTIDAD_DONACION_INVALIDA
    
    -- Prueba caso DONACION_EXCESIVA
    
    -- Prueba caso CANTIDAD_TRASPASO_INVALIDA
    
    -- Prueba caso todo correcto
    declare
      varContenidoRealDonacion      varchar(500);
      varContenidoEsperadoDonacion  varchar(500):= 
        '1,12345678A,,25,10/01/25#2,12345678A,,4,15/01/25#3,77777777B,,35,15/01/25#4,98989898C,,25,25/01/25#5,98765432Y,,35,25/01/25#6,77777777B,,38,' || to_char(trunc(current_date)) || '#7,98765432Y,,26,' || to_char(trunc(current_date)) ;
      varContenidoRealReserva       varchar(500);
      varContenidoEsperadoReserva   varchar(500):= 
        '1,1,3,45#1,2,2,45#1,3,6,52#1,4,,38#2,1,2,5#2,2,1,5#2,3,4,35#2,4,1,35#3,1,6,08#3,2,,82#3,3,10,26#3,4,3,61#4,1,2,6#4,3,8,64#4,4,1,91';
      
    begin
        rollback;
      
        inicializa_test;
        realizarDonacion ('77777777B', 0.38, 4);
        realizarDonacion ('98765432Y', 0.26, 1);
        realizarTraspaso (3, 4, 2, 1.35);

        -- Ver las donaciones esperadas
        SELECT listagg(id_donacion || ',' || nif_donante || ',' || cantidad || ',' || fecha_donacion, '#') 
        WITHIN GROUP (ORDER BY id_donacion) 
        INTO varContenidoRealDonacion 
        FROM donacion;
        
        -- Ver las reservas esperadas
        SELECT listagg(id_tipo_sangre || ',' || id_hospital || ',' || cantidad, '#')
        WITHIN GROUP (ORDER BY id_tipo_sangre, id_hospital)
        INTO varContenidoRealReserva 
        FROM reserva_hospital;

        
        
        if varContenidoRealDonacion=varContenidoEsperadoDonacion and varContenidoRealReserva=varContenidoEsperadoReserva then
            dbms_output.put_line('OK, Sí que modifica bien la BD.'); 
        else
            dbms_output.put_line('KO, No modifica bien la BD.'); 
            dbms_output.put_line('Contenido real Donacion:     '||varContenidoRealDonacion); 
            dbms_output.put_line('Contenido esperado Donacion: '||varContenidoEsperadoDonacion); 
            dbms_output.put_line('Contenido real Reserva hospital:     '||varContenidoRealReserva); 
            dbms_output.put_line('Contenido esperado Reserva hospital: '||varContenidoEsperadoReserva); 
    end if;
      
    exception
      when others then
        dbms_output.put_line('KO, Caso todo OK: '||sqlerrm);
    end;
    
    dbms_output.put_line('----------------------------------------------------');
end;
/


set serveroutput on;

begin
  test_donaciones;
end;


begin
   reset_seq('seq_hospital');
   reset_seq('seq_tipo_sangre');
   reset_seq('seq_donacion');
   reset_seq('seq_traspaso');
end;



begin
   inicializa_test;
end;

-- Mostrar el contenido real de las donaciones
dbms_output.put_line('Contenido real de las donaciones: ' || varContenidoRealDonacion);

-- Mostrar el contenido real de las reservas
dbms_output.put_line('Contenido real de las reservas: ' || varContenidoRealReserva);
