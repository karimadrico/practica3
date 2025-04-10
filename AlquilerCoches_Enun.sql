-- Eliminación de las tablas si existen
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE precio_combustible CASCADE CONSTRAINTS';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -942 THEN RAISE; END IF;
END;

BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE modelos CASCADE CONSTRAINTS';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -942 THEN RAISE; END IF;
END;

BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE vehiculos CASCADE CONSTRAINTS';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -942 THEN RAISE; END IF;
END;

BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE clientes CASCADE CONSTRAINTS';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -942 THEN RAISE; END IF;
END;

BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE facturas CASCADE CONSTRAINTS';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -942 THEN RAISE; END IF;
END;

BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE lineas_factura CASCADE CONSTRAINTS';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -942 THEN RAISE; END IF;
END;

BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE reservas CASCADE CONSTRAINTS';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -942 THEN RAISE; END IF;
END;

-- Eliminar las secuencias si existen
BEGIN
    EXECUTE IMMEDIATE 'DROP SEQUENCE seq_modelos';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -2289 THEN RAISE; END IF;
END;

BEGIN
    EXECUTE IMMEDIATE 'DROP SEQUENCE seq_num_fact';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -2289 THEN RAISE; END IF;
END;

BEGIN
    EXECUTE IMMEDIATE 'DROP SEQUENCE seq_reservas';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -2289 THEN RAISE; END IF;
END;

-- Crear las tablas y secuencias
CREATE TABLE clientes (
    NIF VARCHAR(9) PRIMARY KEY,
    nombre VARCHAR(20) NOT NULL,
    ape1 VARCHAR(20) NOT NULL,
    ape2 VARCHAR(20) NOT NULL,
    direccion VARCHAR(40)
);

CREATE TABLE precio_combustible (
    tipo_combustible VARCHAR(10) PRIMARY KEY,
    precio_por_litro NUMERIC(4,2) NOT NULL
);

CREATE SEQUENCE seq_modelos;

CREATE TABLE modelos (
    id_modelo INTEGER PRIMARY KEY,
    nombre VARCHAR(30) NOT NULL,
    precio_cada_dia NUMERIC(6,2) NOT NULL CHECK (precio_cada_dia >= 0),
    capacidad_deposito INTEGER NOT NULL CHECK (capacidad_deposito > 0),
    tipo_combustible VARCHAR(10) NOT NULL REFERENCES precio_combustible
);

CREATE TABLE vehiculos (
    matricula VARCHAR(8) PRIMARY KEY,
    id_modelo INTEGER NOT NULL REFERENCES modelos,
    color VARCHAR(10)
);

CREATE SEQUENCE seq_reservas;

CREATE TABLE reservas (
    idReserva INTEGER PRIMARY KEY,
    cliente VARCHAR(9) REFERENCES clientes,
    matricula VARCHAR(8) REFERENCES vehiculos,
    fecha_ini DATE NOT NULL,
    fecha_fin DATE,
    CHECK (fecha_fin >= fecha_ini)
);

CREATE SEQUENCE seq_num_fact;

CREATE TABLE facturas (
    nroFactura INTEGER PRIMARY KEY,
    importe NUMERIC(8,2),
    cliente VARCHAR(9) NOT NULL REFERENCES clientes
);

CREATE TABLE lineas_factura (
    nroFactura INTEGER REFERENCES facturas,
    concepto VARCHAR(100),
    importe NUMERIC(8,2),
    PRIMARY KEY (nroFactura, concepto)
);

-- Procedimiento alquilar
CREATE OR REPLACE PROCEDURE alquilar (
    arg_NIF_cliente VARCHAR,
    arg_matricula VARCHAR,
    arg_fecha_ini DATE,
    arg_fecha_fin DATE
)
IS
    -- Variables para los datos del vehículo y modelo
    v_precio_diario NUMERIC;
    v_modelo VARCHAR2(100);
    v_capacidad_litros NUMERIC;
    v_tipo_combustible VARCHAR2(50);
    v_precio_combustible NUMERIC;
    v_n_dias NUMERIC;
    v_importe_total NUMERIC;
    v_id_factura INTEGER;
BEGIN
    -- 1. Validar fechas
    IF arg_fecha_fin IS NOT NULL AND arg_fecha_ini > arg_fecha_fin THEN
        RAISE_APPLICATION_ERROR(-20003, 'El numero de dias sera mayor que cero.');
    END IF;

    -- 2. Seleccionar información del vehículo y bloquearlo
    BEGIN
        SELECT 
            m.nombre AS modelo,
            m.precio_cada_dia,
            m.capacidad_deposito,
            c.tipo_combustible,
            c.precio_por_litro
        INTO 
            v_modelo,
            v_precio_diario,
            v_capacidad_litros,
            v_tipo_combustible,
            v_precio_combustible
        FROM Vehiculos v
        JOIN Modelos m ON v.id_modelo = m.id_modelo
        JOIN Precio_Combustible c ON m.tipo_combustible = c.tipo_combustible
        WHERE v.matricula = arg_matricula
        FOR UPDATE;  -- Bloqueamos el vehículo para evitar solapamientos
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20002, 'Vehiculo inexistente.');
    END;

    -- 3. Verificar si existe reserva solapada
    DECLARE
        v_dummy NUMBER;
    BEGIN
        SELECT 1 INTO v_dummy
        FROM Reservas r
        WHERE r.matricula = arg_matricula
        AND (
            (arg_fecha_ini BETWEEN r.fecha_ini AND NVL(r.fecha_fin, arg_fecha_ini)) OR
            (arg_fecha_fin BETWEEN r.fecha_ini AND NVL(r.fecha_fin, arg_fecha_fin)) OR
            (r.fecha_ini BETWEEN arg_fecha_ini AND NVL(arg_fecha_fin, r.fecha_ini))
        )
        FOR UPDATE;  -- Aseguramos consistencia bloqueando reservas conflictivas

        RAISE_APPLICATION_ERROR(-20004, 'El vehiculo no esta disponible.');
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            NULL; -- No hay conflictos, seguimos
    END;

    -- 4. Insertar en la tabla de reservas
    BEGIN
        INSERT INTO Reservas (cliente, matricula, fecha_ini, fecha_fin)
        VALUES (arg_NIF_cliente, arg_matricula, arg_fecha_ini, arg_fecha_fin);
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -2291 THEN -- Violación de FK: cliente no existe
                RAISE_APPLICATION_ERROR(-20001, 'Cliente inexistente');
            ELSE
                RAISE;
            END IF;
    END;

    -- 5. Crear factura
    IF arg_fecha_fin IS NULL THEN
        v_n_dias := 4;  -- Si la fecha de fin es NULL, asumimos 4 días
    ELSE
        v_n_dias := arg_fecha_fin - arg_fecha_ini;
    END IF;

    -- Calcular el importe total
    v_importe_total := (v_n_dias * v_precio_diario) + (v_capacidad_litros * v_precio_combustible);

    -- Insertar la factura
    INSERT INTO Facturas (importe, cliente)
    VALUES (v_importe_total, arg_NIF_cliente)
    RETURNING nroFactura INTO v_id_factura;

    -- Insertar las líneas de la factura
    -- Línea 1: Días de alquiler
    INSERT INTO Lineas_Factura (NroFactura, concepto, importe)
    VALUES (
        v_id_factura,
        v_n_dias || ' días de alquiler vehículo modelo ' || v_modelo,
        v_n_dias * v_precio_diario
    );

    -- Línea 2: Depósito lleno
    INSERT INTO Lineas_Factura (NroFactura, concepto, importe)
    VALUES (
        v_id_factura,
        'Depósito lleno (' || v_capacidad_litros || ' litros de ' || v_tipo_combustible || ')',
        v_capacidad_litros * v_precio_combustible
    );

    COMMIT;
END;
