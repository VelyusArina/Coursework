CREATE OR REPLACE FUNCTION validate_employee_contact()
RETURNS TRIGGER AS $$
BEGIN
    -- Проверка на валидность телефона и email
    IF NEW.phone_number ~ E'^\\+?[0-9\\-]+$' AND NEW.email ~ E'^[A-Za-z0-9._%-]+@[A-Za-z0-9.-]+\\.[A-Z|a-z]{2,4}$' THEN
        RETURN NEW;  -- Если валидно, ничего не меняем
    ELSE
        -- Замена на контактные данные автосалона
        SELECT email, phone_number INTO NEW.email, NEW.phone_number
        FROM car_dealership
        WHERE id = NEW.car_dealership_id;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER before_insert_order
BEFORE INSERT ON "my_order"
FOR EACH ROW
EXECUTE FUNCTION validate_employee_contact();

CREATE OR REPLACE FUNCTION update_order_status()
RETURNS TRIGGER AS $$
BEGIN
    -- Если информация о транзакции содержит "оплата не прошла"
    IF NEW.transaction_info ILIKE '%оплата не прошла%' THEN
        -- Обновляем статус заказа на "заказ ожидает оплаты"
        UPDATE "my_order"
        SET status_order = 'В ожидании оплаты'
        WHERE id = NEW.order_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_order_status_trigger
AFTER INSERT ON "payment"
FOR EACH ROW
EXECUTE FUNCTION update_order_status();

CREATE OR REPLACE FUNCTION update_order_status_on_zero_inventory()
RETURNS TRIGGER AS $$
BEGIN
    -- Проверка, что заказ связан с автозапчастью
    IF NEW.autopart_id IS NOT NULL THEN
        -- Проверка, что количество на складе равно 0
        IF (SELECT count FROM autopart WHERE id = NEW.autopart_id) = 0 THEN
            -- Устанавливаем статус заказа в "ожидается заказ деталей"
            UPDATE "my_order"
            SET status_order = 'Ожидается заказ деталей'
            WHERE id = NEW.id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_order_status_trigger
BEFORE INSERT ON "my_order"
FOR EACH ROW
EXECUTE FUNCTION update_order_status_on_zero_inventory();


CREATE OR REPLACE FUNCTION update_car_color_on_completed_order()
RETURNS TRIGGER AS $$
BEGIN
    -- Проверка, что заказ завершен и связан с услугой "покраска автомобиля"
    IF NEW.status_order = 'Завершено' AND
       (SELECT name_service FROM service WHERE id = NEW.service_id) = 'покраска автомобиля' THEN
        -- Обновляем цвет автомобиля в связанной записи в таблице "car"
        UPDATE car
        SET colour = (SELECT description_service FROM service WHERE id = NEW.service_id)
        WHERE id = NEW.car_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_car_color_trigger
AFTER INSERT ON "my_order"
FOR EACH ROW
EXECUTE FUNCTION update_car_color_on_completed_order();

CREATE OR REPLACE FUNCTION delete_car_and_possession_on_client_delete()
RETURNS TRIGGER AS $$
BEGIN
    -- Проверка наличия связанных записей в сущности "владение"
    IF EXISTS (SELECT 1 FROM possession WHERE client_id = OLD.id) THEN
        -- Удаление записей в сущности "владение"
        DELETE FROM possession WHERE client_id = OLD.id;

        -- Проверка и удаление связанных записей в сущности "автомобиль", если у автомобиля больше нет владельцев
        DELETE FROM car
        WHERE id IN (SELECT car_id FROM possession GROUP BY car_id HAVING COUNT(*) = 0);
    END IF;

    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

-- Создание триггера
CREATE TRIGGER delete_car_and_possession_trigger
AFTER DELETE ON "client"
FOR EACH ROW
EXECUTE FUNCTION delete_car_and_possession_on_client_delete();

