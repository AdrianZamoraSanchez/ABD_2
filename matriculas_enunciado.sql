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

    -- Detección de duplicidad de matrícula
    begin
        select 1 into v_dni
        from matricula
        where dni_alumno = p_dni_alumno
          and id_edicion = p_id_edicion
          and estado in ('CONFIRMADA', 'ESPERA');

        raise_application_error(-20004, 'El alumno ya tiene una matricula activa en la edicion.');
    exception
        when no_data_found then
            null;
    end;

    -- Estado matrícula
    if v_plazas_oc < v_plazas_max then
        v_estado_mat := 'CONFIRMADA';

        update edicion_curso
        set plazas_ocupadas = plazas_ocupadas + 1
        where id_edicion = p_id_edicion;
    else
        v_estado_mat := 'ESPERA';
    end if;
    
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
end;
/

create or replace procedure cancelar_matricula(
    p_id_matricula  matricula.id_matricula%type
) is
    v_estado      matricula.estado%type;
    v_id_edicion  matricula.id_edicion%type;
    v_id_bloqueo  matricula.id_edicion%type;
    v_id_espera   matricula.id_edicion%type;
begin
    -- Obtención de la matrícula
    begin
        select estado, id_edicion
        into v_estado, v_id_edicion
        from matricula
        where id_matricula = p_id_matricula;
    exception
        when no_data_found then
            raise_application_error(-20005, 'Matricula inexistente.');
    end;

    -- Comprobación de martícula cancelada previamente
    if v_estado = 'CANCELADA' then
        raise_application_error(-20006, 'La matricula ya estaba cancelada.');
    end if;

    -- Bloqueo de la edición
    select id_edicion into v_id_bloqueo
    from edicion_curso
    where id_edicion = v_id_edicion
    for update;

    -- Cancelación
    update matricula
    set estado = 'CANCELADA'
    where id_matricula = p_id_matricula;

    -- Gestión de la matrícula ya confirmada
    if v_estado = 'CONFIRMADA' then
        update edicion_curso 
        set plazas_ocupadas = plazas_ocupadas - 1 
        where id_edicion = v_id_edicion;

        begin
            select id_matricula
            into v_id_espera
            from (
                select id_matricula
                from matricula
                where id_edicion = v_id_edicion
                  and estado = 'ESPERA'
                order by fecha_matricula, id_matricula
            )
            where rownum = 1;

            -- Confirmar matrícula en espera
            update matricula
            set estado = 'CONFIRMADA'
            where id_matricula = v_id_espera;

            update edicion_curso
            set plazas_ocupadas = plazas_ocupadas + 1
            where id_edicion = v_id_edicion;
            
        end;
    end if;
end;
/

create or replace procedure registrar_pago(
    p_id_matricula  matricula.id_matricula%type,
    p_importe       pago_matricula.importe%type
) is
    v_estado   matricula.estado%type;
    v_importe  matricula.importe%type;

    e_pago_duplicado exception;
    pragma exception_init(e_pago_duplicado, -1); -- Error ORA-00001 para violación de UNIQUE
begin
    -- Comprobación matrícula
    begin
        select estado, importe
        into v_estado, v_importe
        from matricula
        where id_matricula = p_id_matricula;
    exception
        when no_data_found then
            raise_application_error(-20005, 'Matricula inexistente.');
    end;

    -- Error pago de matrícula no confirmada
    if v_estado <> 'CONFIRMADA' then
        raise_application_error(-20007, 'Solo se pueden pagar matriculas confirmadas.');
    end if;

    -- Comprobar importe correcto
    if p_importe <> v_importe then
        raise_application_error(-20008, 'El importe abonado no coincide con la matricula.');
    end if;

    -- Insertar pago correcto
    insert into pago_matricula
    values (
        seq_pago.nextval,
        p_id_matricula,
        sysdate,
        p_importe
    );

    -- Captura de error por duplicado
    exception
        when e_pago_duplicado then
            raise_application_error(-20009, 'La matricula ya ha sido abonada.');
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

create or replace procedure test_matricular_alumno is
begin
    -- Caso 1: alumno inexistente
    begin
        inicializa_test;
        matricular_alumno('12345678B', 1);
    exception
        when others then
            if sqlcode = -20001 then
                dbms_output.put_line('OK: alumno inexistente');
            else
                dbms_output.put_line('ERROR no esperado para alumno inexistente:' || sqlerrm);
            end if;
    end;

    -- Caso 2: edición inexistente
    begin
        inicializa_test;
        matricular_alumno('11111111A', 999);
    exception
        when others then
            if sqlcode = -20002 then
                dbms_output.put_line('OK: edición inexistente');
            else
                dbms_output.put_line('ERROR no esperado para edición inexistente:' || sqlerrm);
            end if;
    end;

    -- Caso 3: matrícula duplicada
    begin
        inicializa_test;
        matricular_alumno('11111111A', 1);
    exception
        when others then
            if sqlcode = -20004 then
                dbms_output.put_line('OK: duplicidad' );
            else
                dbms_output.put_line('ERROR no esperado para duplicidad en matrícula:' || sqlerrm);
            end if;
    end;

    -- Caso 4: matrícula en espera
    declare
        v_count number;
    begin
        inicializa_test;

        matricular_alumno('11111111A', 4);

        select count(*) into v_count
        from matricula
        where dni_alumno = '11111111A'
        and id_edicion = 4
        and estado = 'ESPERA';

        if v_count = 1 then
            dbms_output.put_line('OK: matrícula en espera');
        else
            dbms_output.put_line('ERROR: matrícula espera');
        end if;
    end;

    -- Caso 5: matrícula confirmada
    declare
        v_count number;
    begin
        inicializa_test;

        matricular_alumno('55555555E', 1);

        select count(*) into v_count
        from matricula
        where dni_alumno = '55555555E'
        and id_edicion = 1
        and estado = 'CONFIRMADA';

        if v_count = 1 then
            dbms_output.put_line('OK: matrícula confirmada');
        else
            dbms_output.put_line('ERROR: matrícula confirmada');
        end if;
    end;

        -- Caso 6: matricula con edición cerrada
    begin
        inicializa_test;
        matricular_alumno('11111111A', 3);
    exception
        when others then
            if sqlcode = -20003 then
                dbms_output.put_line('OK: edición cerrada');
            else
                dbms_output.put_line('ERROR no esperado para edición cerrada: ' || sqlerrm);
            end if;
    end;
end;
/

create or replace procedure test_cancelar_matricula is
begin
    -- Caso 1: alumno inexistente
    begin
        inicializa_test;
        cancelar_matricula(123);
    exception
        when others then
            if sqlcode = -20005 then
                dbms_output.put_line('OK: matrícula inexistente');
            else
                dbms_output.put_line('ERROR no esperado para matrícula inexistente:' || sqlerrm);
            end if;
    end;

    -- Caso 2: Matrícula ya cancelada
    begin
        inicializa_test;
        cancelar_matricula(4);
    exception
        when others then
            if sqlcode = -20006 then
                dbms_output.put_line('OK: matrícula cancelada');
            else
                dbms_output.put_line('ERROR no esperado para matrícula cancelada:' || sqlerrm);
            end if;
    end;

    -- Caso 3: matrícula en espera
    declare 
        v_estado   varchar2(12);
    begin
        inicializa_test;

        cancelar_matricula(3);

        select estado into v_estado
        from matricula
        where id_matricula = 3;

        if v_estado = 'CANCELADA' then
            dbms_output.put_line('OK: cancelar en espera');
        else
            dbms_output.put_line('ERROR: cancelar en espera');
        end if;
    end;
    
    -- Caso 4: matrícula formalizada desde espera
    declare 
        v_estado   varchar2(12);
    begin
        inicializa_test;

        cancelar_matricula(2);

        select estado into v_estado
        from matricula
        where id_matricula = 3;

        if v_estado = 'CONFIRMADA' then
            dbms_output.put_line('OK: matrícula confirmada desde espera');
        else
            dbms_output.put_line('ERROR: matrícula confirmada desde espera');
        end if;
    end;
    
end;
/

create or replace procedure test_registrar_pago is
begin
    -- Caso 1: Pago sobre matrícula inexistente
    begin
        inicializa_test;
        registrar_pago(999, 100);
    exception
        when others then
            if sqlcode = -20005 then
                dbms_output.put_line('OK: pago matrícula inexistente');
            else
                dbms_output.put_line('ERROR no esperado para pago matrícula inexistente: ' || sqlerrm);
            end if;
    end;

    -- Caso 2: Pago sobre matrícula no confirmada
    begin
        inicializa_test;
        registrar_pago(3, 180);
    exception
        when others then
            if sqlcode = -20007 then
                dbms_output.put_line('OK: pago no confirmada');
            else
                dbms_output.put_line('ERROR no esperado para pago no confirmada:' || sqlerrm);
            end if;
    end;

    -- Caso 3: Pago duplicado
    begin
        inicializa_test;
        registrar_pago(1, 120);
    exception
        when others then
            if sqlcode = -20009 then
                dbms_output.put_line('OK: pago duplicado');
            else
                dbms_output.put_line('ERROR no esperado para pago duplicado: ' || sqlerrm);
            end if;
    end;

    -- Caso 4: Pago correcto
    declare
        v_count number;
    begin
        inicializa_test;

        matricular_alumno('22222222B', 1);
        registrar_pago(8, 120);

        select count(*) into v_count
        from pago_matricula
        where id_matricula = 8;

        if v_count = 1 then
            dbms_output.put_line('OK: pago correcto');
        else
            dbms_output.put_line('ERROR: pago correcto');
        end if;
    end;

    -- Caso 5: Pago con importe incorrecto
    begin
        inicializa_test;
        registrar_pago(1, 999);
    exception
        when others then
            if sqlcode = -20008 then
                dbms_output.put_line('OK: importe incorrecto');
            else
                dbms_output.put_line('ERROR no esperado para importe incorrecto: ' || sqlerrm);
            end if;
    end;
end;
/

-- Test de integración del sistema (comprueba inserciones + updates + estados finales)
create or replace procedure test_caso_final is
    v_estado_mat   varchar2(12);
    v_plazas       number;
    v_pagos        number;
begin
    inicializa_test;

    -- Nueva matrícula confirmada
    matricular_alumno('55555555E', 1);

    -- Debe haberse creado matrícula con id 8
    registrar_pago(8, 120);

    -- Se cancela la matrícula confirmada previamente (id 2)
    -- Debe promocionar la 3 desde espera
    cancelar_matricula(2);

    -- Se verifica promoción de matricula 3
    select estado into v_estado_mat
    from matricula
    where id_matricula = 3;

    -- Se verifica número de plazas de la edición 2
    select plazas_ocupadas into v_plazas
    from edicion_curso
    where id_edicion = 2;

    -- Se verifica pago creado
    select count(*) into v_pagos
    from pago_matricula
    where id_matricula = 8;

    if v_estado_mat = 'CONFIRMADA'
       and v_plazas = 1
       and v_pagos = 1 then
        dbms_output.put_line('OK: test integración correcto');
    else
        dbms_output.put_line('ERROR en test de integración');
    end if;
end;
/

set serveroutput on

-- Tests del procedimiento: matricular_alumno
exec test_matricular_alumno;

-- Tests del procedimiento: cancelar_matricula
exec test_cancelar_matricula;

-- Tests del procedimiento: registrar_pago
exec test_registrar_pago;

-- Test de integración
exec test_caso_final;