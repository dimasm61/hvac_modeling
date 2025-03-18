set search_path = modeling;

create or replace function get_exchanger_efficiency(
    air_flow float, temp_out_door float, temp_in_door float, max_efficiency float)
    returns float
as
$$
declare
    v_factor float;
    t_factor float;
    dt float;
    air_flow_max float = 300;
begin
    /*
    примерная модель: КПД рекуператор зависит от:
     - разницы температур
     - воздушного потока

    Примем что номинальный расчётный воздухообмен рекуператора air_flow_max - 300кубов.
    Чем выше расход - ниже КПД, ниже расход - больше КПД.
         50кубов - 1.00
        100кубов - 0.85
        200кубов - 0.70
        300кубов - 0.65

    Чем больше разница температур, тем больше КПД
        30°С - 1.00
        25°С - 0.95
        20°С - 0.90
        15°С - 0.85
        10°С - 0.80
         5°С - 0.75
         1°С - 0.70

    Итоговый КПД - перемножение этих двух параметров с идеальным КПД 90%
     */

    v_factor := 1;

    if air_flow between 0 and 50 then
        v_factor := 1.00;
    elseif air_flow between  50 and 100 then
        v_factor := 0.85;
    elseif air_flow between 100 and 200 then
        v_factor := 0.70;
    elseif air_flow between 200 and 300 then
        v_factor := 0.65;
    elseif air_flow > 300 then
        v_factor := 0.5;
    end if;

    dt := temp_in_door - temp_out_door;

    if dt < 0 then
        dt := 0;
    end if;

    t_factor := 1;

    if dt between 25 and 30 then
        t_factor := 1.00;
    elseif dt between 20 and 25 then
        t_factor := 0.95;
    elseif dt between 15 and 20 then
        t_factor := 0.90;
    elseif dt between 10 and 15 then
        t_factor := 0.85;
    elseif dt between 5 and 10 then
        t_factor := 0.80;
    elseif dt between 1 and 5 then
        t_factor := 0.75;
    elseif dt between  0 and 1 then
        t_factor := 0.70;
    end if;

    return max_efficiency * v_factor * t_factor;
end
$$ language plpgsql;

create or replace function get_exchanger_temp(efficiency float, temp_out_door float, temp_in_door float)
    returns float
as
$$
declare
    dt float;
begin
    dt := temp_in_door - temp_out_door;
    if dt < 0 then
        dt := 0;
    end if;

    return temp_out_door + dt * efficiency;
end;
$$ language plpgsql;

create or replace function get_indoor_temperature_by_day(outdoorTemp float, t timestamp) returns float
as
$$
declare
    h int;
    d int;
    dw int;
    m int;
begin
    h := date_part('hour', t);
    d := date_part('day', t);
    dw := date_part('isodow', t);
    m := date_part('month', t);


    if outdoorTemp <= 5 then
        -- если на улице ниже 5, то греем

        -- если выходные то греем ночью до 17 а днём до 23
        if dw in (6,7) then
            if h between 7 and 23 then
                return 20;
            end if;

            if h in (24,0,1,2,3,4,5,6) then
                return 17;
            end if;
        end if;

        -- будние дни - греем до 5 градусов
        return 5;
    else
        -- на улице выше 5 градусов - не греем, весна, лето
        return outdoorTemp;
    end if;

end
$$ language plpgsql;


create or replace function get_air_exchange_by_hour_and_speed(t timestamp) returns float
as
$$
declare
    h       int;
    m       int;
    -- расходы на разных скоростях, кубов в час
    speed_1 int = 100;
    speed_2 int = 200;
    speed_3 int = 300;
begin
    m := date_part('month', t);
    h := date_part('hour', t);

    -- летом греть не нужно, дуем на полную скорость, днём 3-я, ночью 2-я
    -- зимой подогрев, экономим, дуем меньше, днём 2-я, ночью 1-я

    -- зима
    if (m between 1 and 4) or (m between 10 and 12) then
        if h between 7 and 23 then
            return speed_2; -- day
        else
            return speed_1; -- night
        end if;
    end if;

    -- лето
    if m between 4 and 9 then
        if h between 7 and 23 then
            return speed_3; -- day
        else
            return speed_2; -- night
        end if;
    end if;

    return speed_3;
end
$$ language plpgsql;

create or replace function get_kwh_for_heating(v float, dt float) returns float as
$$
begin
    -- мощность требуемую для нагрева v кубов в час на дельту dt градусов
    -- 1000 кубов в час нагреть на 100∘С нужно 33.5кВтч
    return 0.000335 * v * dt;
end
$$ language plpgsql;

create or replace function get_kwh_cost_day_or_night(t timestamp, dayCost decimal(10, 2), nightCost decimal(10, 2))
    returns decimal(10, 2) as
$$
declare
    h int;
begin
    h := date_part('hour', t);

    if h between 7 and 22 then
        return dayCost;
    end if;

    return nightCost;
end
$$ language plpgsql;

create or replace function get_kwh_cost(t timestamp) returns float as
$$
begin
    -- https://khb-rkc.ru/тарифы/
    -- Тарифы на электрическую энергию для населения на 2025 год, руб./кВТ*ч
    -- Население, проживающее в городах в домах, оборудованных стационарными электроплитами
    -- и электроотопительными установками (с сентября по май)
    -- до 3900
    -- 25й (2-е полугодие) - 4.75р
    -- 25й (1-е полугодие) - 4.22р
    -- 24й (2-е полугодие) - 4,22
    -- 24й (1-е полугодие) - 3,88
    -- с 01.12.2022 по 31.12.2023 - 3,88
    -- с 01.07.2022 по 30.11.2022 - 3,56
    -- с 01.01.2022 по 30.06.2022 - 3,44

    if t > '2025-06-01'::timestamp then
        return get_kwh_cost_day_or_night(t, 4.75, 4.75);
    end if;

    if t > '2024-06-01'::timestamp then
        return get_kwh_cost_day_or_night(t, 4.22, 4.22);
    end if;

    if t > '2023-06-01'::timestamp then
        return get_kwh_cost_day_or_night(t, 3.88, 3.88);
    end if;

    if t > '2022-06-01'::timestamp then
        return get_kwh_cost_day_or_night(t, 3.56, 3.56);
    end if;

    return get_kwh_cost_day_or_night(t, 3.44, 3.44);

end
$$ language plpgsql;

