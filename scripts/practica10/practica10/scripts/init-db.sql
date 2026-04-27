-- ═══════════════════════════════════════════════════════════
-- Práctica 10 — Script de inicialización PostgreSQL
-- Se ejecuta automáticamente la primera vez que el contenedor
-- arranca (docker-entrypoint-initdb.d)
-- ═══════════════════════════════════════════════════════════

-- Base de datos ya creada por POSTGRES_DB en el compose
\c reprobados_db;

-- ── Tabla de usuarios del dominio ───────────────────────────
CREATE TABLE IF NOT EXISTS usuarios (
    id          SERIAL PRIMARY KEY,
    usuario     VARCHAR(50)  UNIQUE NOT NULL,
    nombre      VARCHAR(100) NOT NULL,
    apellido    VARCHAR(100) NOT NULL,
    email       VARCHAR(150),
    depto       VARCHAR(50),
    creado_en   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ── Datos iniciales (los mismos del CSV de la práctica 9) ───
INSERT INTO usuarios (usuario, nombre, apellido, email, depto) VALUES
    ('jperez',     'Juan',     'Perez',     'jperez@reprobados.local',     'Cuates'),
    ('mlopez',     'Maria',    'Lopez',     'mlopez@reprobados.local',     'Cuates'),
    ('cgarcia',    'Carlos',   'Garcia',    'cgarcia@reprobados.local',    'Cuates'),
    ('amartinez',  'Ana',      'Martinez',  'amartinez@reprobados.local',  'Cuates'),
    ('lrodriguez', 'Luis',     'Rodriguez', 'lrodriguez@reprobados.local', 'Cuates'),
    ('shernandez', 'Sofia',    'Hernandez', 'shernandez@reprobados.local', 'NoCuates'),
    ('dgonzalez',  'Diego',    'Gonzalez',  'dgonzalez@reprobados.local',  'NoCuates'),
    ('vtorres',    'Valeria',  'Torres',    'vtorres@reprobados.local',    'NoCuates'),
    ('mramirez',   'Miguel',   'Ramirez',   'mramirez@reprobados.local',   'NoCuates'),
    ('fflores',    'Fernanda', 'Flores',    'fflores@reprobados.local',    'NoCuates')
ON CONFLICT (usuario) DO NOTHING;

-- ── Tabla de log de accesos (para auditoría) ────────────────
CREATE TABLE IF NOT EXISTS log_accesos (
    id          SERIAL PRIMARY KEY,
    usuario     VARCHAR(50) NOT NULL,
    accion      VARCHAR(100),
    ip_origen   INET,
    resultado   VARCHAR(20) DEFAULT 'OK',
    registrado  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Verificación
SELECT 'Inicialización completada: ' || COUNT(*) || ' usuarios cargados' AS status
FROM usuarios;
