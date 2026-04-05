drop table pago_matricula cascade constraints;
drop table matricula cascade constraints;
drop table edicion_curso cascade constraints;
drop table curso cascade constraints;
drop table alumno cascade constraints;

drop sequence seq_pago;
drop sequence seq_matricula;
drop sequence seq_edicion;
drop sequence seq_curso;

create table alumno(
    dni      varchar2(9) primary key,
    nombre   varchar2(20) not null,
    ape1     varchar2(20) not null,
    ape2     varchar2(20) not null,
    email    varchar2(60) not null unique
);

create sequence seq_curso;

create table curso(
    id_curso     number primary key,
    nombre       varchar2(60) not null,
    horas        number not null check (horas > 0),
    precio_base  number(8,2) not null check (precio_base >= 0)
);

create sequence seq_edicion;

create table edicion_curso(
    id_edicion       number primary key,
    id_curso         number not null references curso(id_curso),
    fecha_inicio     date not null,
    fecha_fin        date not null,
    plazas_maximas   number not null check (plazas_maximas > 0),
    plazas_ocupadas  number not null check (plazas_ocupadas >= 0),
    estado           varchar2(10) not null check (estado in ('ABIERTA', 'CERRADA')),
    check (fecha_fin >= fecha_inicio),
    check (plazas_ocupadas <= plazas_maximas)
);

create sequence seq_matricula;

create table matricula(
    id_matricula    number primary key,
    dni_alumno      varchar2(9) not null references alumno(dni),
    id_edicion      number not null references edicion_curso(id_edicion),
    fecha_matricula date not null,
    estado          varchar2(12) not null check (estado in ('CONFIRMADA', 'ESPERA', 'CANCELADA')),
    importe         number(8,2) not null check (importe >= 0)
);

create sequence seq_pago;

create table pago_matricula(
    id_pago        number primary key,
    id_matricula   number not null references matricula(id_matricula),
    fecha_pago     date not null,
    importe        number(8,2) not null check (importe >= 0),
    constraint uq_pago_matricula unique (id_matricula)
);
/

create or replace procedure matricular_alumno(
    p_dni_alumno  alumno.dni%type,
    p_id_edicion  edicion_curso.id_edicion%type
) is
    v_dni         alumno.dni%type;
    v_estado_ed   edicion_curso.estado%type;
    v_plazas_max  edicion_curso.plazas_maximas%type;
    v_plazas_oc   edicion_curso.plazas_ocupadas%type;
    v_precio      curso.precio_base%type;
    v_estado_mat  matricula.estado%type;
begin
    -- Comprobar alumno existente
    begin
        select dni into v_dni
        from alumno
        where dni = p_dni_alumno;
    exception
        when no_data_found then
            raise_application_error(-20001, 'Alumno inexistente.');
    end;

    -- Comprobar el estado de una edición de un curso
    begin
        select e.estado, e.plazas_maximas, e.plazas_ocupadas, c.precio_base
        into v_estado_ed, v_plazas_max, v_plazas_oc, v_precio
        from edicion_curso e
        join curso c on c.id_curso = e.id_curso
        where e.id_edicion = p_id_edicion
        for update;
    exception
        when no_data_found then
            raise_application_error(-20002, 'Edicion inexistente.');
    end;

    -- Error por edición en estado diferente de abierta
    if v_estado_ed <> 'ABIERTA' then
        raise_application_error(-20003, 'La edicion no admite matriculas.');
    end if;

    -- TODO: definir estado matrícula
    -- Inserción de matrícula 
    insert into matricula
    values (
        seq_matricula.nextval,
        p_dni_alumno,
        p_id_edicion,
        sysdate,
        v_estado_mat,
        v_precio
    );

    null;
end;
/

create or replace procedure cancelar_matricula(
    p_id_matricula  matricula.id_matricula%type
) is
begin
    null;
end;
/

create or replace procedure registrar_pago(
    p_id_matricula  matricula.id_matricula%type,
    p_importe       pago_matricula.importe%type
) is
begin
    null;
end;
/

create or replace procedure reset_seq(p_seq_name varchar2)
is
    l_val number;
begin
    execute immediate
        'select ' || p_seq_name || '.nextval from dual'
        into l_val;

    execute immediate
        'alter sequence ' || p_seq_name || ' increment by -' || l_val || ' minvalue 0';

    execute immediate
        'select ' || p_seq_name || '.nextval from dual'
        into l_val;

    execute immediate
        'alter sequence ' || p_seq_name || ' increment by 1 minvalue 0';
end;
/

create or replace procedure inicializa_test is
begin
    reset_seq('seq_curso');
    reset_seq('seq_edicion');
    reset_seq('seq_matricula');
    reset_seq('seq_pago');

    delete from pago_matricula;
    delete from matricula;
    delete from edicion_curso;
    delete from curso;
    delete from alumno;

    insert into alumno values ('11111111A', 'Ana',   'Lopez',    'Martin',  'ana@ubu.es');
    insert into alumno values ('22222222B', 'Bruno', 'Perez',    'Santos',  'bruno@ubu.es');
    insert into alumno values ('33333333C', 'Carla', 'Ruiz',     'Mora',    'carla@ubu.es');
    insert into alumno values ('44444444D', 'Diego', 'Alonso',   'Gil',     'diego@ubu.es');
    insert into alumno values ('55555555E', 'Elena', 'Serrano',  'Vega',    'elena@ubu.es');

    insert into curso values (seq_curso.nextval, 'Bases de Datos',   30, 120);
    insert into curso values (seq_curso.nextval, 'PL/SQL Avanzado',  40, 180);
    insert into curso values (seq_curso.nextval, 'DevOps',           25, 150);

    insert into edicion_curso values (seq_edicion.nextval, 1, date '2026-04-01', date '2026-05-15', 2, 1, 'ABIERTA');
    insert into edicion_curso values (seq_edicion.nextval, 2, date '2026-04-10', date '2026-06-10', 1, 1, 'ABIERTA');
    insert into edicion_curso values (seq_edicion.nextval, 3, date '2026-05-01', date '2026-06-01', 2, 0, 'CERRADA');
    insert into edicion_curso values (seq_edicion.nextval, 2, date '2026-06-15', date '2026-07-30', 2, 2, 'ABIERTA');

    insert into matricula values (seq_matricula.nextval, '11111111A', 1, date '2026-02-01', 'CONFIRMADA', 120);
    insert into matricula values (seq_matricula.nextval, '22222222B', 2, date '2026-02-02', 'CONFIRMADA', 180);
    insert into matricula values (seq_matricula.nextval, '33333333C', 2, date '2026-02-03', 'ESPERA',     180);
    insert into matricula values (seq_matricula.nextval, '44444444D', 3, date '2026-02-04', 'CANCELADA',  150);
    insert into matricula values (seq_matricula.nextval, '44444444D', 4, date '2026-02-05', 'CONFIRMADA', 180);
    insert into matricula values (seq_matricula.nextval, '55555555E', 4, date '2026-02-06', 'CONFIRMADA', 180);
    insert into matricula values (seq_matricula.nextval, '33333333C', 4, date '2026-02-07', 'ESPERA',     180);

    insert into pago_matricula values (seq_pago.nextval, 1, date '2026-02-10', 120);
    insert into pago_matricula values (seq_pago.nextval, 2, date '2026-02-11', 180);

    commit;
end;
/

exec inicializa_test;
