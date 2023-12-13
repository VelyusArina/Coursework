--- Функция регистрации клиента
CREATE OR REPLACE FUNCTION create_client(
    p_full_name VARCHAR(64),
    p_birth_date DATE,
    p_gender gender_enum,
    p_email VARCHAR(64),
    p_phone_number VARCHAR(20),
    p_password VARCHAR(64),
    p_car_model model_car
)
RETURNS INTEGER AS
$$
DECLARE
    new_client_id INTEGER;
BEGIN
    INSERT INTO client (full_name, birth_date, gender, email, phone_number, password)
    VALUES (p_full_name, p_birth_date, p_gender, p_email, p_phone_number, p_password)
    RETURNING id INTO new_client_id;

    -- Добавить информацию о машине клиента в таблицу possession
    INSERT INTO possession (client_id, car_id)
    VALUES (new_client_id, (SELECT id FROM car WHERE model = p_car_model));

    RETURN new_client_id;
END;
$$
LANGUAGE plpgsql;

---Доступ к личному кабинету клиента
CREATE OR REPLACE FUNCTION get_client_profile(
    p_email VARCHAR(64),
    p_password VARCHAR(64)
)
RETURNS TABLE (
    id INTEGER,
    full_name VARCHAR(64),
    birth_date DATE,
    gender gender_enum,
    email VARCHAR(64),
    phone_number VARCHAR(20),
    car_model model_car
) AS
$$
BEGIN
    RETURN QUERY
    SELECT
        c.id,
        c.full_name,
        c.birth_date,
        c.gender,
        c.email,
        c.phone_number,
        cp.model
    FROM
        client c
    JOIN possession cp ON c.id = cp.client_id
    WHERE
        c.email = p_email
        AND c.password = p_password;
END;
$$
LANGUAGE plpgsql;

--- Функция аутентификации клиента
CREATE OR REPLACE FUNCTION authenticate_client(
    p_email VARCHAR(64),
    p_password VARCHAR(64)
)
RETURNS BOOLEAN AS
$$
DECLARE
    is_authenticated BOOLEAN;
BEGIN
    SELECT TRUE
    INTO is_authenticated
    FROM client
    WHERE email = p_email AND password = p_password;

    RETURN is_authenticated;
END;
$$
LANGUAGE plpgsql;


--- Выборка доступных услуг для марки машины
CREATE OR REPLACE FUNCTION get_available_services(
    p_car_model model_car
)
RETURNS TABLE (
    service_id INTEGER,
    name_service VARCHAR(64),
    description_service TEXT,
    price INTEGER
) AS
$$
BEGIN
    RETURN QUERY
    SELECT
        s.id AS service_id,
        s.name_service,
        s.description_service,
        s.price
    FROM
        service s
    WHERE
        s.autopart_id IN (SELECT id FROM autopart WHERE model = p_car_model);
END;
$$
LANGUAGE plpgsql;

--- Выборка доступных дат и времени
CREATE OR REPLACE FUNCTION get_available_dates_and_times(
    p_service_id INTEGER
)
RETURNS TABLE (
    available_date DATE,
    available_time TIME
) AS
$$
BEGIN
    RETURN QUERY
    SELECT
        d.available_date,
        t.available_time
    FROM
        (
            SELECT DISTINCT
                date_trunc('day', datetime_order) AS available_date
            FROM
                my_order
            WHERE
                status_order = 'Новое'
                AND service_id = p_service_id
        ) d
    CROSS JOIN LATERAL (
        SELECT
            generate_series('09:00'::TIME, '17:00'::TIME, '30 minutes'::INTERVAL) AS available_time
    ) t
    LEFT JOIN my_order o ON d.available_date = date_trunc('day', o.start_time)
        AND t.available_time = date_trunc('hour', o.start_time)::TIME
        AND o.service_id = p_service_id
    WHERE
        o.id IS NULL;
END;
$$
LANGUAGE plpgsql;

---Регистрация записи клиента и ожидание подтверждения предоплатой
CREATE OR REPLACE FUNCTION register_client_order(
    p_client_id INTEGER,
    p_service_id INTEGER,
    p_chosen_date DATE,
    p_chosen_time TIME,
    p_sum_price INTEGER,
    p_description_payment TEXT
)
RETURNS INTEGER AS
$$
DECLARE
    new_order_id INTEGER;
BEGIN
    -- Регистрация записи клиента
    INSERT INTO my_order (datetime_order, status_order, start_time, service_id, client_id)
    VALUES (NOW(), 'Новое', p_chosen_date + p_chosen_time, p_service_id, p_client_id)
    RETURNING id INTO new_order_id;

    -- Создание записи о предоплате
    INSERT INTO payment (sum_price, datetime_payment, description_payment, order_id)
    VALUES (p_sum_price, NOW(), p_description_payment, new_order_id);

    RETURN new_order_id;
END;
$$
LANGUAGE plpgsql;

--- Функция для обновления статуса заказа
CREATE OR REPLACE FUNCTION update_order_status_and_notify(
    p_order_id INTEGER,
    p_new_status status_order_enum
)
RETURNS VOID AS
$$
DECLARE
    v_car_id INTEGER;
    v_client_email VARCHAR(64);
    v_notification_subject VARCHAR(255);
    v_notification_body TEXT;
BEGIN
    -- Обновление статуса заказа
    UPDATE my_order
    SET
        status_order = p_new_status
    WHERE
        id = p_order_id;

    -- Получение информации о клиенте и заказе
    SELECT
        o.car_id,
        s.name_service
    INTO
        v_car_id,
        v_notification_subject
    FROM
        my_order o
    JOIN car c ON o.car_id = c.id
    JOIN service s ON o.service_id = s.id
    WHERE
        o.id = p_order_id;

    -- Подготовка текста уведомления
    v_notification_body := 'Уважаемый клиент,\n\n';
    v_notification_body := v_notification_body || 'Статус вашего заказа на услугу "' || v_notification_subject || '" был изменен на "' || p_new_status || '".\n\n';
    v_notification_body := v_notification_body || 'Спасибо за выбор наших услуг!';
    
    END;
$$
LANGUAGE plpgsql;

--- Изменение статуса заказа
SELECT update_order_status_and_notify(123, 'В обработке');

---Автосервис ведет учет доступных автозапчастей и их статуса (в наличии или на заказ).

--- получить информацию о всех автозапчастях и их статусе
SELECT
    id,
    name_autopart,
    description_autopart,
    model,
    price,
    count,
    CASE
        WHEN count > 0 THEN 'В наличии'
        ELSE 'На заказ'
    END AS status
FROM
    autopart;

--- процедура для предварительной оплаты
CREATE OR REPLACE FUNCTION make_prepayment(
    p_order_id INTEGER,
    p_amount INTEGER
)
RETURNS VOID AS
$$
BEGIN
    -- Обновление статуса заказа на "В ожидании оплаты"
    UPDATE my_order
    SET
        status_order = 'В ожидании оплаты'
    WHERE
        id = p_order_id;

    -- Создание записи о предварительной оплате
    INSERT INTO payment (sum_price, datetime_payment, order_id, description_payment)
    VALUES (p_amount, NOW(), p_order_id, 'Предварительная оплата');
END;
$$
LANGUAGE plpgsql;

--- Процедура для окончательной оплаты
CREATE OR REPLACE FUNCTION make_final_payment(
    p_order_id INTEGER,
    p_amount INTEGER
)
RETURNS VOID AS
$$
BEGIN
    -- Обновление статуса заказа на "Завершено"
    UPDATE my_order
    SET
        status_order = 'Завершено'
    WHERE
        id = p_order_id;

    -- Создание записи об окончательной оплате
    INSERT INTO payment (sum_price, datetime_payment, order_id, description_payment)
    VALUES (p_amount, NOW(), p_order_id, 'Окончательная оплата');
END;
$$
LANGUAGE plpgsql;

--- процедура для регистрации запроса на чат
CREATE OR REPLACE FUNCTION register_chat_request(
    p_client_id INTEGER
)
RETURNS INTEGER AS
$$
DECLARE
    new_chat_request_id INTEGER;
BEGIN
    -- Регистрация нового запроса на чат
    INSERT INTO chat_request (client_id, datetime_request)
    VALUES (p_client_id, NOW())
    RETURNING id INTO new_chat_request_id;

    RETURN new_chat_request_id;
END;
$$
LANGUAGE plpgsql;

---Хранимая процедура для регистрации запроса на обратный звонок
CREATE OR REPLACE FUNCTION register_callback_request(
    p_client_id INTEGER
)
RETURNS INTEGER AS
$$
DECLARE
    new_callback_request_id INTEGER;
BEGIN
    -- Регистрация нового запроса на обратный звонок
    INSERT INTO callback_request (client_id, datetime_request)
    VALUES (p_client_id, NOW())
    RETURNING id INTO new_callback_request_id;

    RETURN new_callback_request_id;
END;
$$
LANGUAGE plpgsql;
