-- Basic application functions

CREATE OR REPLACE FUNCTION add_department(IN a_did INTEGER, a_dname TEXT)
    RETURNS VOID AS
$$
BEGIN
    INSERT INTO Departments VALUES (a_did, a_dname);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION remove_department --trigger: before_remove_department
    (IN did1 INTEGER)
    RETURNS VOID AS
$$
DECLARE
BEGIN
    DELETE FROM Departments WHERE did = did1;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION add_room
    (IN room_num INTEGER, floor_num INTEGER, room_name TEXT, dep_id INTEGER,
                                    room_cap INTEGER)
    RETURNS VOID AS
$$
BEGIN
    INSERT INTO Meeting_Rooms VALUES (room_num, floor_num, room_name, dep_id, room_cap);
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION change_capacity --trigger function is updating_updates()
(IN up_date TEXT, up_cap INTEGER, up_room INTEGER, up_floor INTEGER, up_mid INTEGER)
    RETURNS VOID AS
$$
BEGIN
    INSERT INTO updates VALUES (to_date(up_date, 'YYYY/MM/DD'), up_cap, up_room, up_floor, up_mid);
    UPDATE meeting_rooms
    SET cap = up_cap
    WHERE room = up_room
      AND floor = up_floor;

END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION add_employee -- triggers: not_junior, manager_not_senior, senior_not_manager
(IN new_did INTEGER, new_ename TEXT, new_home_contact INTEGER, new_mobile_contact INTEGER, new_office_contact INTEGER,
 kind VARCHAR(7))
    RETURNS VOID AS
$$
DECLARE
    new_eid   INTEGER;
    new_email TEXT;
BEGIN
    IF (SELECT COUNT(*) FROM employees) = 0 THEN
        SELECT 1 INTO new_eid;
    ELSEIF (SELECT COUNT(*) FROM employees) > 0 THEN
        SELECT MAX(eid) + 1 FROM employees INTO new_eid;
    END IF;

    SELECT 'e2021_' || cast(new_eid as text) || '@company.com' INTO new_email;

    INSERT INTO employees(eid, did, ename, email, home_contact, mobile_contact, office_contact)
    VALUES (new_eid, new_did, new_ename, new_email, new_home_contact, new_mobile_contact, new_office_contact);
    IF (lower(kind) = 'junior') THEN
        INSERT INTO junior VALUES (new_eid);
    ELSEIF (lower(kind) = 'senior') THEN
        INSERT INTO booker VALUES (new_eid);
        INSERT INTO senior VALUES (new_eid);
    ELSEIF (lower(kind) = 'manager') THEN
        INSERT INTO booker VALUES (new_eid);
        INSERT INTO manager VALUES (new_eid);
    END IF;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION remove_employee
    (IN del_eid INTEGER, del_date TEXT)
    RETURNS VOID AS
$$
DECLARE
    count_book     INTEGER;
    count_non_book INT;
BEGIN
    SELECT COUNT(*)
    INTO count_book
    FROM booker
    WHERE eid = del_eid;
    SELECT COUNT(*)
    INTO count_non_book
    FROM junior
    WHERE eid = del_eid;
    UPDATE employees
    SET resigned_date = to_date(del_date, 'YYYY-MM-DD'),
        did = 0
    WHERE eid = del_eid;
    IF (count_book = 1) THEN
        DELETE
        FROM booker
        WHERE eid = del_eid;
    ELSEIF (count_non_book = 1) THEN
        DELETE
        FROM junior
        WHERE eid = del_eid;
    END IF;
END;

$$ LANGUAGE plpgsql;

-- Basic functions triggers

CREATE OR REPLACE FUNCTION updating_updates()
    RETURNS TRIGGER AS
$$
DECLARE
    record_count INT;
    manager_did  INTEGER := (SELECT did
                             FROM employees
                             WHERE eid = NEW.mid);
    room_did     INTEGER := (SELECT did
                             FROM meeting_rooms
                             WHERE room = NEW.room
                               AND floor = NEW.floor);
BEGIN
    IF NEW.date < current_date THEN
        RAISE EXCEPTION 'You cannot change room capacity in the past';
    ELSEIF (manager_did <> room_did) THEN
        RAISE EXCEPTION 'You are not the manager of the department for this room.';
    END IF;
    SELECT COUNT(*)
    INTO record_count
    FROM updates
    WHERE room = NEW.room
      AND floor = NEW.floor
      AND date = NEW.date
    GROUP BY date, room, floor;

    IF (record_count > 0) THEN
        UPDATE updates
        SET new_cap = NEW.new_cap
        WHERE room = NEW.room
          AND floor = NEW.floor
          AND date = NEW.date;
        RETURN NULL;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_cap
    BEFORE INSERT
    ON updates
    FOR EACH ROW
EXECUTE FUNCTION updating_updates();


CREATE OR REPLACE FUNCTION delete_oversized_meetings()
    RETURNS TRIGGER AS
$$
BEGIN
    DELETE
    FROM sessions s1
    WHERE (date, stime) IN (
        SELECT date, stime
        FROM sessions s2
                 INNER JOIN joins j USING (room, floor, date, stime)
        WHERE (NEW.date < s2.date OR
               (NEW.date = s2.date AND SUBSTRING(CAST(stime AS TEXT), 1, 2) >
                                       SUBSTRING(CAST(current_timestamp AS TEXT), 12, 2)))
        GROUP BY(room, floor, date, stime)
        HAVING NEW.new_cap < COUNT(*)
    )
      AND NEW.room = s1.room
      AND NEW.floor = s1.floor;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER capacity_has_changed
    BEFORE INSERT OR UPDATE
    ON updates
    FOR EACH ROW
EXECUTE FUNCTION delete_oversized_meetings();

CREATE OR REPLACE FUNCTION delete_meetings()
    RETURNS TRIGGER AS
$$
BEGIN
    DELETE
    FROM Joins
    WHERE eid = NEW.eid
      AND (date >= NEW.resigned_date OR (date = NEW.resigned_date AND stime > current_time));
    DELETE
    FROM Sessions
    WHERE eid = NEW.eid
      AND (date >= NEW.resigned_date OR (date = NEW.resigned_date AND stime > current_time));
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER delete_for_resigned
    AFTER UPDATE
    ON Employees
    FOR EACH ROW
    WHEN (NEW.resigned_date IS NOT NULL)
EXECUTE FUNCTION delete_meetings();

CREATE OR REPLACE FUNCTION not_junior()
    RETURNS TRIGGER AS
$$
DECLARE
    count INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO count
    FROM Junior
    WHERE NEW.eid = Junior.eid;

    IF count > 0 THEN
        RAISE EXCEPTION 'Employee % is currently a junior', NEW.eid;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER booker_not_junior --for add_employee (enforce ISA junior OR Booker)
    BEFORE INSERT OR UPDATE
    ON Booker
    FOR EACH ROW
EXECUTE FUNCTION not_junior();

CREATE OR REPLACE FUNCTION not_booker()
    RETURNS TRIGGER AS
$$
DECLARE
    count       INTEGER;
    resignation DATE := NULL;
BEGIN
    SELECT COUNT(*)
    INTO count
    FROM booker
    WHERE NEW.eid = booker.eid;

    SELECT resigned_date
    INTO resignation
    FROM employees
    WHERE eid = NEW.eid;

    IF count > 0 THEN
        RAISE EXCEPTION 'Employee % is currently a booker', NEW.eid;
    ELSEIF resignation IS NOT NULL THEN
        RAISE EXCEPTION 'Employee % has resigned', NEW.eid;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER junior_not_booker --for add_employee (enforce ISA junior OR Booker)
    BEFORE INSERT OR UPDATE
    ON junior
    FOR EACH ROW
EXECUTE FUNCTION not_booker();

CREATE OR REPLACE FUNCTION only_manager()
    RETURNS TRIGGER AS
$$
DECLARE
    scount INTEGER;
    bcount INTEGER;

BEGIN
    SELECT COUNT(*)
    INTO scount
    FROM Senior
    WHERE NEW.eid = Senior.eid;

    SELECT COUNT(*)
    INTO Bcount
    FROM Booker
    WHERE NEW.eid = Booker.eid;

    IF scount > 0 THEN --cannot be a senior
        RAISE EXCEPTION 'Employee % is already a senior.', NEW.eid;
    ELSEIF bcount = 0 THEN --must be a booker, again, FK constraint
        RAISE EXCEPTION 'Employee is not in booker table';
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER manager_not_senior --for add_employee (enforce ISA senior OR manager)
    BEFORE INSERT OR UPDATE
    ON Manager
    FOR EACH ROW
EXECUTE FUNCTION only_manager();

CREATE OR REPLACE FUNCTION only_senior()
    RETURNS TRIGGER AS
$$
DECLARE
    mcount INTEGER;
    bcount INTEGER;

BEGIN
    SELECT COUNT(*)
    INTO mcount
    FROM Manager
    WHERE NEW.eid = Manager.eid;

    SELECT COUNT(*)
    INTO Bcount
    FROM Booker
    WHERE NEW.eid = Booker.eid;

    IF mcount > 0 THEN --cannot be a manager
        RAISE EXCEPTION 'Employee % is already a manager.', NEW.eid;
    ELSEIF bcount = 0 THEN
        RETURN NULL;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER senior_not_manager --for add_employee (enforce ISA senior OR manager)
    BEFORE INSERT OR UPDATE
    ON Senior
    FOR EACH ROW
EXECUTE FUNCTION only_senior();

CREATE OR REPLACE FUNCTION cannot_delete_employee()
    RETURNS TRIGGER AS
$$
BEGIN
    RAISE EXCEPTION 'If employee has retired, use remove_employee function instead since employee records must be kept.';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER keep_employee_record
    BEFORE DELETE
    ON employees
EXECUTE FUNCTION cannot_delete_employee();

--Core functions
CREATE OR REPLACE FUNCTION search_room --return SELECT * FROM another_function
(IN search_capacity INT, search_date TEXT, search_start INT, search_end INT)
    RETURNS TABLE
            (
                floor_number  INT,
                room_number   INT,
                department_id INT,
                room_capacity INT
            )
AS
$$
DECLARE
    start_time time := to_timestamp(concat(search_start, ':00:00'), 'HH24:MI:SS')::TIME;
    end_time   time := to_timestamp(concat(search_end, ':00:00'), 'HH24:MI:SS')::TIME;
BEGIN
    RETURN QUERY SELECT floor, room, did, cap
                 FROM meeting_rooms
                 WHERE (floor, room) NOT IN (
                     SELECT floor, room
                     FROM sessions
                     WHERE date = to_date(search_date, 'yyyy/mm/dd')
                       AND start_time <= stime
                       AND stime < end_time
                 )
                   AND search_capacity <= cap
                 ORDER BY cap;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION book_room --trigger: booking_check
(IN bdate TEXT, starthour INT, endhour INT, broom INTEGER, bfloor INTEGER, b_eid INTEGER)
    RETURNS VOID AS
$$
DECLARE
    temp INT := starthour; end_time INT := endhour;
BEGIN
    IF endhour = 00 THEN
        end_time = 24;
    END IF;
    WHILE (temp < end_time)
        LOOP
            INSERT INTO Sessions
            VALUES (TO_DATE(bdate, 'yyyy/mm/dd'),
                    TO_TIMESTAMP(CONCAT(temp, ':00:00'), 'HH24:MI:SS')::TIME, broom, bfloor, b_eid);
            temp := temp + 1;
        END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION unbook_room --trigger: unbook_check
(IN udate TEXT, starthour INT, endhour INT, uroom INTEGER, ufloor INTEGER, u_eid INTEGER)
    RETURNS VOID AS
$$
DECLARE
    temp INT = starthour;
BEGIN
    IF endhour = 00 THEN
        endhour = 24;
    END IF;

    WHILE temp < CAST(endhour AS int)
        LOOP
            DELETE
            FROM Sessions
            WHERE u_eid = eid
              AND uroom = room
              AND ufloor = floor
              AND date = to_date(udate, 'yyyy/mm/dd')
              AND stime = (interval '01:00' * temp)::TIME;
            temp := temp + 1;
        END LOOP;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION approve_meeting --trigger: approval_check
(IN bdate TEXT, starttime INT, endtime INT, broom INTEGER, bfloor INTEGER, b_Mid INTEGER)
    RETURNS VOID AS
$$
DECLARE
    end_hour INT := endtime;
    temp     INT := starttime;
BEGIN
    IF endtime = 00 THEN
        end_hour := 24;
    END IF;
    WHILE (temp < end_hour)
        LOOP
            INSERT INTO Approves
            VALUES (to_date(bdate, 'yyyy/mm/dd'),
                    (interval '01:00' * temp)::TIME, broom, bfloor, b_Mid);
            temp := temp + 1;
        END LOOP;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION join_meeting --trigger: check_join
(IN jdate TEXT, starthour INT, endhour INT, jroom INTEGER, jfloor INTEGER, j_id INTEGER)
    RETURNS VOID AS
$$
DECLARE
    temp INT := starthour; end_time INT := endhour;
BEGIN
    IF (endhour = 00) THEN --JIC time SG uses is 0000, not 2400
        end_time := 24;
    END IF;
    WHILE (temp < end_time)
        LOOP
            INSERT INTO Joins
            VALUES (to_date(jdate, 'yyyy/mm/dd'),
                    to_timestamp(concat(temp, ':00:00'), 'HH24:MI:SS')::TIME, j_id, jroom, jfloor);
            temp := temp + 1;
        END LOOP;

END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION leave_meeting --trigger: leave_check
(IN jdate TEXT, starthour INT, endhour INT, jroom INTEGER, jfloor INTEGER, j_id INTEGER)
    RETURNS VOID AS
$$
DECLARE
    temp INT := starthour; end_time INT := endhour;
BEGIN
    IF (endhour = 00) THEN
        end_time := 24;
    END IF;

    WHILE (temp < end_time)
        LOOP
            DELETE
            FROM Joins
            WHERE to_date(jdate, 'yyyy/mm/dd') = date
              AND stime = to_timestamp(concat(temp, ':00:00'), 'HH24:MI:SS')::TIME
              AND jroom = room
              AND jfloor = floor
              AND j_id = eid;
            temp := temp + 1;
        END LOOP;
END;
$$ LANGUAGE plpgsql;

--Core triggers

CREATE OR REPLACE FUNCTION check_booking()
    RETURNS TRIGGER AS
$$
DECLARE
    trace_date DATE;
    resigned   DATE;
    count      INTEGER;
    starthour  TIME := NEW.stime;
    bdate      DATE := NEW.date;
BEGIN
    SELECT traced_date
    INTO trace_date
    FROM Employees
    WHERE eid = NEW.eid;

    SELECT resigned_date
    INTO resigned
    FROM Employees
    WHERE eid = NEW.eid;

    SELECT COUNT(*)
    INTO count
    FROM Approves
    WHERE NEW.stime = stime
      AND NEW.date = date
      AND NEW.room = room
      AND NEW.floor = floor;

    IF (bdate < current_date) THEN
        RAISE NOTICE 'You cannot book a date that is earlier than the present.';
        RETURN NULL;
    ELSEIF (bdate = current_date AND
            starthour <= current_time) THEN
        RAISE NOTICE 'You cannot book a time earlier than the present';
        RETURN NULL;
    ELSEIF (current_date - trace_date <= 7) THEN
        RAISE NOTICE 'Close contacts or employees with fevers cannot book rooms';
        RETURN NULL;
    ELSEIF resigned IS NOT NULL THEN
        RAISE NOTICE 'Resigned employees cannot book rooms';
        RETURN NULL;
    ELSEIF count > 0 THEN --already booked by someone else
        RAISE NOTICE 'Room has already been booked at this time';
        RETURN NULL;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER booking_check
    BEFORE INSERT OR UPDATE
    ON Sessions
    FOR EACH ROW
EXECUTE FUNCTION check_booking();

CREATE OR REPLACE FUNCTION can_we_unbook()
    RETURNS TRIGGER AS
$$
BEGIN
    IF (old.date < current_date) THEN
        RAISE NOTICE 'Records of past meetings should be kept';
        RETURN NULL;
    ELSEIF (old.date = current_date AND SUBSTRING(CAST(old.stime AS TEXT), 1, 2) <=
                                        SUBSTRING(CAST(current_timestamp AS TEXT), 12, 2)) THEN
        RAISE NOTICE 'Records of past meetings should be kept';
        RETURN NULL;
    ELSE
        DELETE
        FROM Joins
        WHERE floor = OLD.floor
          AND room = OLD.room
          AND date = OLD.date
          AND stime = OLD.stime;
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER unbook_check
    BEFORE DELETE
    ON Sessions
    FOR EACH ROW
EXECUTE FUNCTION can_we_unbook();

CREATE OR REPLACE FUNCTION check_approval()
    RETURNS TRIGGER AS
$$
DECLARE
    rm_did        INTEGER;
    m_did         INTEGER;
    num_attendees INTEGER;
    rm_capacity   INTEGER;
BEGIN
    SELECT did
    INTO rm_did
    FROM Meeting_Rooms
    WHERE NEW.floor = floor
      AND NEW.room = room;

    SELECT did
    INTO m_did
    FROM Employees
    WHERE NEW.eid = eid;

    SELECT COUNT(*)
    INTO num_attendees
    FROM Joins
    WHERE NEW.stime = stime
      AND NEW.date = date
      AND NEW.room = room
      AND NEW.floor = floor;

    SELECT cap
    INTO rm_capacity
    FROM Meeting_Rooms
    WHERE NEW.room = room
      AND NEW.floor = floor;

    IF NEW.eid IS NULL THEN
        RAISE NOTICE 'A manager must approve the meeting via approve_meeting function';
        RETURN NULL;
    ELSEIF rm_did <> m_did THEN
        RAISE NOTICE 'Only Managers from the same department can approve bookings';
        RETURN NULL;
    ELSEIF NEW.date < current_date THEN
        RAISE NOTICE 'You can only approve future meetings';
        RETURN NULL;
    ELSEIF NEW.date = current_date AND
           SUBSTRING(CAST(NEW.stime AS TEXT), 1, 2) <= SUBSTRING(CAST(current_timestamp AS TEXT), 12, 2) THEN
        RAISE NOTICE 'You can only approve future meetings';
        RETURN NULL;
    ELSEIF rm_capacity < num_attendees THEN
        RAISE NOTICE 'Maximum room capacity exceeded!';
        RETURN NULL;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER approval_check
    BEFORE INSERT OR UPDATE
    ON Approves
    FOR EACH ROW
EXECUTE FUNCTION check_approval();

CREATE OR REPLACE FUNCTION add_booker() -- automatically add booker into Joins
    RETURNS TRIGGER AS
$$
BEGIN
    INSERT INTO Joins VALUES (NEW.date, NEW.stime, NEW.eid, NEW.room, NEW.floor);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER booker_join
    AFTER INSERT
    ON Sessions
    FOR EACH ROW
EXECUTE FUNCTION add_booker();

CREATE OR REPLACE FUNCTION check_join()
    RETURNS TRIGGER AS
$$
DECLARE
    a_count          INTEGER;
    s_count          INTEGER;
    trace_date       DATE;
    rm_capacity      INT;
    num_attendees    INT;
    resignation_date DATE;
BEGIN
    SELECT COUNT(*)
    INTO a_count
    FROM Approves
    WHERE NEW.date = date
      AND NEW.stime = stime
      AND NEW.room = room
      AND NEW.floor = floor;

    SELECT COUNT(*)
    INTO S_count
    FROM Sessions
    WHERE NEW.date = date
      AND NEW.stime = stime
      AND NEW.room = room
      AND NEW.floor = floor;

    SELECT traced_date
    INTO trace_date
    FROM Employees
    WHERE NEW.eid = eid;

    SELECT cap
    INTO rm_capacity
    FROM Meeting_Rooms
    WHERE NEW.room = room
      AND NEW.floor = floor;

    SELECT COUNT(*)
    INTO num_attendees
    FROM Joins
    WHERE NEW.stime = stime
      AND NEW.date = date
      AND NEW.room = room
      AND NEW.floor = floor;

    SELECT resigned_date
    INTO resignation_date
    FROM Employees
    WHERE NEW.eid = eid;

    IF a_count > 0 THEN
        RAISE NOTICE 'Approved meetings cannot be joined';
        RETURN NULL;
    ELSEIF s_count = 0 THEN
        RAISE NOTICE 'This slot has not been booked yet';
        RETURN NULL;
    ELSEIF NEW.date < current_date THEN
        RAISE NOTICE 'You cannot join a meeting in the past';
        RETURN NULL;
    ELSEIF (NEW.date = current_date AND SUBSTRING(CAST(NEW.stime AS TEXT), 1, 2) <=
                                        SUBSTRING(CAST(current_timestamp AS TEXT), 12, 2)) THEN
        RAISE NOTICE 'You cannot join a meeting in the past';
        RETURN NULL;
    ELSEIF ((NEW.date - trace_date) < 7 AND trace_date IS NOT NULL) THEN
        RAISE EXCEPTION 'Close contacts cannot join meetings for 7 days';
    ELSEIF (NOT EXISTS(SELECT *
                       FROM Health_Declaration
                       WHERE eid = NEW.eid
                         AND date = current_date)) THEN
        RAISE EXCEPTION 'Employees must declare temperature to join meetings';
    ELSEIF num_attendees >= rm_capacity THEN
        RAISE EXCEPTION 'This meeting is at full capacity';
    ELSEIF resignation_date <= NEW.date THEN
        RAISE EXCEPTION 'Employee has resigned and thus cannot join the meeting.';
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER join_check
    BEFORE INSERT
    ON Joins
    FOR EACH ROW
EXECUTE FUNCTION check_join();

CREATE OR REPLACE FUNCTION check_leave()
    RETURNS TRIGGER AS
$$
DECLARE
    a_count     INTEGER;
    s_count     INTEGER;
    trace_date  DATE;
    resignation DATE;

BEGIN

    SELECT COUNT(*)
    INTO a_count
    FROM Approves
    WHERE OLD.date = date
      AND OLD.stime = stime
      AND OLD.room = room
      AND OLD.floor = floor;

    SELECT COUNT(*)
    INTO s_count
    FROM Sessions
    WHERE OLD.date = date
      AND OLD.stime = stime
      AND OLD.room = room
      AND OLD.floor = floor;

    SELECT traced_date
    INTO trace_date
    FROM Employees
    WHERE OLD.eid = eid;

    SELECT resigned_date
    INTO resignation
    FROM Employees
    WHERE OLD.eid = eid;

    IF (old.date < current_date) THEN
        RAISE NOTICE 'You cannot leave a past meeting';
        RETURN NULL;
    ELSEIF (old.date = current_date AND SUBSTRING(CAST(old.stime AS TEXT), 1, 2) <=
                                        SUBSTRING(CAST(current_timestamp AS TEXT), 12, 2)) THEN
        RAISE NOTICE 'You cannot leave a past meeting';
        RETURN NULL;
    ELSEIF (resignation IS NOT NULL) THEN
        RAISE NOTICE 'Employee has resigned';
        RETURN OLD;
    ELSEIF (SELECT e.resigned_date
            FROM (Joins j JOIN Sessions s USING (date, stime, room, floor))
                     JOIN Employees e ON s.eid = e.eid
            WHERE j.eid = OLD.eid
            LIMIT 1) IS NOT NULL THEN
        RAISE NOTICE 'Booker of this meeting has resigned';
        RETURN OLD;
    ELSEIF (current_date - (SELECT e.traced_date
                            FROM (Joins j JOIN Sessions s USING (date, stime, room, floor))
                                     JOIN Employees e ON s.eid = e.eid
                            WHERE j.eid = OLD.eid
                              AND date = OLD.date
                              AND stime = OLD.stime
                              AND room = OLD.room
                              AND floor = OLD.floor
                            LIMIT 1) <= 7) THEN
        RAISE NOTICE 'Booker of this meeting has a fever or is a close contact';
        RETURN OLD;
    ELSEIF (s_count = 0) THEN
        RAISE NOTICE 'Booker has unbooked meeting';
        RETURN OLD;
    ELSEIF (trace_date IS NOT NULL AND (current_date - trace_date <= 7)) THEN
        RAISE NOTICE 'Employee leaves approved meeting due to fever';
        RETURN OLD;
    ELSEIF (a_count > 0) THEN
        RAISE NOTICE 'You cannot leave an approved meeting';
        RETURN NULL;
    ELSE
        RETURN OLD;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER leave_check
    BEFORE DELETE
    ON Joins
    FOR EACH ROW
EXECUTE FUNCTION check_leave();


-- Health functions

CREATE OR REPLACE FUNCTION declare_health -- trigger declare_again
    (IN ddate TEXT, deid INTEGER, dtemp NUMERIC(3, 1))
    RETURNS VOID AS
$$
BEGIN
    INSERT INTO Health_Declaration VALUES (to_date(ddate, 'yyyy/mm/dd'), deid, dtemp);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION contact_tracing(IN id INT, trace_date TEXT)
    RETURNS TABLE
            (employee_id INT)
AS
$$
DECLARE
    tdate             DATE;
    DECLARE high_temp NUMERIC(3, 1);
BEGIN
    SELECT to_date(trace_date, 'yyyy/mm/dd') INTO tdate;
    SELECT temp INTO high_temp FROM health_declaration WHERE id = eid and tdate = date;

    IF (high_temp < 37.5) THEN
        RAISE EXCEPTION 'Employee % has no fever!', id;
    ELSEIF high_temp IS NULL THEN
        RAISE EXCEPTION 'Employee % did not declare temperature for the date provided.', id;
    ELSEIF tdate > CURRENT_DATE THEN
        RAISE EXCEPTION 'You cannot do contact tracing for a future date.';
    END IF;

    --leave all future meetings where they are not the booker
    DELETE FROM Joins WHERE eid = id AND (date >= tdate OR (date = tdate AND stime > current_time));

    --cancel all future bookings (from sessions <- cascade to joins & approves)
    DELETE FROM Sessions WHERE eid = id AND (date >= tdate OR (date = tdate AND stime > current_time));


    UPDATE Employees --ensuring employees cannot join meetings for the next 7 days
    SET traced_date = tdate
    WHERE eid IN (SELECT j.eid
                  FROM Joins j,
                       Approves a
                  WHERE tdate - a.date <= 3
                    AND tdate - a.date > 0
                    AND j.room = a.room
                    AND j.floor = a.floor
                    AND j.date = a.date
                    AND j.stime = a.stime);

    --contact all employees in the same approved meeting from the past 3 days & remove them from
    --meetings for the next 7 days
    --return table of close contact eids

    DELETE
    FROM Joins
    WHERE eid IN (SELECT j.eid
                  FROM Joins j,
                       Approves a
                  WHERE tdate - a.date <= 3
                    AND tdate - a.date > 0
                    AND j.room = a.room
                    AND j.floor = a.floor
                    AND j.date = a.date
                    AND j.stime = a.stime)
      AND (date <= tdate + 7 AND date >= tdate);

    RETURN QUERY (SELECT DISTINCT j.eid
                  FROM Joins j,
                       Approves a
                  WHERE tdate - a.date <= 3
                    AND tdate - a.date > 0
                    AND j.room = a.room
                    AND j.floor = a.floor
                    AND j.date = a.date
                    AND j.stime = a.stime);
END;
$$ LANGUAGE plpgsql;


-- Health triggers

CREATE OR REPLACE FUNCTION check_fever()
    RETURNS TRIGGER AS
$$
BEGIN
    IF (NEW.temp > 37.5) THEN
        UPDATE Employees
        SET traced_date=NEW.date
        WHERE eid = NEW.eid;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER fever_status
    BEFORE INSERT OR UPDATE
    ON Health_Declaration
    FOR EACH ROW
EXECUTE FUNCTION check_fever();

CREATE OR REPLACE FUNCTION check_declaration()
    RETURNS TRIGGER AS
$$
BEGIN
    IF (SELECT resigned_date
        FROM employees
        WHERE eid = NEW.eid) < current_date THEN
        RAISE NOTICE 'Retired employees should not declare health';
        RETURN NULL;
    END IF;
    IF NEW.date <= CURRENT_DATE THEN
        RETURN NEW;
    ELSE
        RAISE EXCEPTION 'Please do not declare temperature in the future';
    END IF;
END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER declaration_check
    BEFORE INSERT OR UPDATE
    ON Health_Declaration
    FOR EACH ROW
EXECUTE FUNCTION check_declaration();

CREATE OR REPLACE FUNCTION declare_again_fun()
    RETURNS TRIGGER AS
$$
BEGIN
    IF EXISTS(
            SELECT 1
            FROM health_declaration
            WHERE date = NEW.date
              AND eid = NEW.eid
        )
    THEN
        UPDATE health_declaration
        SET temp = NEW.temp
        WHERE eid = NEW.eid
          AND date = NEW.date;
        RETURN NULL;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER declare_again
    BEFORE INSERT
    ON health_declaration
    FOR EACH ROW
EXECUTE FUNCTION declare_again_fun();

CREATE OR REPLACE FUNCTION cannot_delete_health()
    RETURNS TRIGGER AS
$$
BEGIN
    IF (OLD.date < current_date) THEN
        RAISE NOTICE 'You cannot delete past declarations.';
        RETURN NULL;
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER keep_health
    BEFORE DELETE
    ON health_declaration
    FOR EACH ROW
EXECUTE FUNCTION cannot_delete_health();

-- Admin functions
CREATE OR REPLACE FUNCTION non_compliance(IN start_date TEXT, end_date TEXT)
    RETURNS TABLE
            (
                employee_id    INTEGER,
                number_of_days INTEGER
            )
AS
$$
DECLARE
    max_days INT := to_date(end_date, 'yyyy/mm/dd') + 1 - to_date(start_date, 'yyyy-mm-dd');
BEGIN
    RETURN QUERY (SELECT e.eid employee_id, (max_days - COUNT(*)::INT) days_declared
                  FROM health_declaration h
                           INNER JOIN employees e
                                      USING (eid)
                  WHERE (to_date(start_date, 'yyyy-mm-dd') <= date AND date <= to_date(end_date, 'yyyy/mm/dd'))
                    AND (e.resigned_date IS NULL OR e.resigned_date > current_date)
                  GROUP BY e.eid
                  HAVING max_days - COUNT(*)::INT <> 0
                  UNION
                  (SELECT e1.eid employee_id, max_days days_declared
                   FROM employees e1
                   WHERE e1.eid NOT IN (
                       SELECT eid
                       FROM health_declaration
                       WHERE (to_date(start_date, 'yyyy-mm-dd') <= date AND date <= to_date(end_date, 'yyyy/mm/dd')))
                     AND (e1.resigned_date IS NULL OR e1.resigned_date > current_date))
                  ORDER BY days_declared DESC, employee_id);
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION view_booking_report(IN start_date TEXT, employee_id INT)
    RETURNS TABLE
            (
                floor       INT,
                room        INT,
                date        DATE,
                start_hour  INTEGER,
                is_approved BOOLEAN
            )
AS
$$
BEGIN
    RETURN QUERY (SELECT s.floor,
                         s.room,
                         s.date,
                         CAST(substring(CAST(s.stime AS TEXT), 1, 2) AS INT),
                         (CASE
                              WHEN a.floor IS NULL
                                  THEN FALSE
                              ELSE TRUE END) AS is_approved
                  FROM Sessions s
                           LEFT OUTER JOIN Approves a USING (floor, room, date, stime)
                  WHERE s.eid = employee_id
                    AND s.date >= to_date(start_date, 'YYYY/MM/DD')
                  ORDER BY s.date, s.stime
    );
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION view_future_meeting(IN start_date TEXT, employee_id INT)
    RETURNS TABLE
            (
                floor      INT,
                room       INT,
                date       DATE,
                start_hour INTEGER
            )
AS
$$
BEGIN
    RETURN QUERY (SELECT a.floor, a.room, a.date, CAST(substring(CAST(a.stime AS TEXT), 1, 2) AS INT)
                  FROM Approves a
                           JOIN Joins j USING (floor, room, date, stime)
                  WHERE j.eid = employee_id
                    AND a.date >= to_date(start_date, 'YYYY/MM/DD')
                  ORDER BY a.date, a.stime
    );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION view_manager_report(IN start_date TEXT, em_id INT)
    RETURNS TABLE
            (
                floor      INT,
                room       INT,
                date       DATE,
                start_hour INTEGER,
                employee_id       INT
            )
AS
$$
DECLARE
    e_did INT;
BEGIN
    SELECT did
    INTO e_did
    FROM Employees
    WHERE eid = em_id;

    RETURN QUERY (SELECT s.floor, s.room, s.date, CAST(substring(CAST(s.stime AS TEXT), 1, 2) AS INT), s.eid
                  FROM Sessions s
                           LEFT OUTER JOIN Approves a USING (floor, room, date, stime)
                           NATURAL JOIN Meeting_Rooms m
                  WHERE a.floor IS NULL
                    AND e_did = m.did
                    AND em_id IN (SELECT eid FROM Manager WHERE eid = em_id)
                    AND s.date >= to_date(start_date, 'YYYY/MM/DD')
                  ORDER BY s.date, s.stime
    );
END;
$$ LANGUAGE plpgsql;

