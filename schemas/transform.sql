\c reviews

DROP TABLE IF EXISTS meta CASCADE;
DROP TABLE IF EXISTS characteristics CASCADE;


/* --------------------------- Create additional tables --------------------------- */

CREATE TABLE meta (
  product_id INT GENERATED BY DEFAULT AS IDENTITY UNIQUE PRIMARY KEY,
  recommended INT DEFAULT 0,
  not_recommended INT DEFAULT 0,
  rating_1 INT DEFAULT 0,
  rating_2 INT DEFAULT 0,
  rating_3 INT DEFAULT 0,
  rating_4 INT DEFAULT 0,
  rating_5 INT DEFAULT 0
) WITH (
  OIDS=FALSE
);

CREATE TABLE characteristics (
  id INT GENERATED BY DEFAULT AS IDENTITY UNIQUE PRIMARY KEY,
  name VARCHAR(15) UNIQUE
) WITH (
  OIDS=FALSE
);


/* -------------------------- FILL CHARACTERISTICS TABLE -------------------------- */

INSERT INTO characteristics (id, name)
  SELECT id, characteristic_name
  FROM product_characteristics_join
  ON CONFLICT (name) DO NOTHING;


/* -------- add new characteristic_id to the proudct_characteristics_join table -------- */

ALTER TABLE product_characteristics_join DROP COLUMN IF EXISTS characteristic_id;
ALTER TABLE product_characteristics_join DROP COLUMN IF EXISTS total_score;
ALTER TABLE product_characteristics_join DROP COLUMN IF EXISTS total_votes;
ALTER TABLE product_characteristics_join ADD COLUMN characteristic_id INT references characteristics(id);
ALTER TABLE product_characteristics_join ADD COLUMN total_score INT DEFAULT 0;
ALTER TABLE product_characteristics_join ADD COLUMN total_votes INT DEFAULT 0;

UPDATE product_characteristics_join
  SET characteristic_id = c.id
  FROM characteristics c
  WHERE c.name = characteristic_name;


/* ------------------- load final characteristics_review table ------------------- */

ALTER TABLE characteristics_reviews DROP COLUMN IF EXISTS characteristic_id;
ALTER TABLE characteristics_reviews ADD COLUMN characteristic_id INT references characteristics(id);

-- Be patient, this one takes awhile --
UPDATE characteristics_reviews
  SET characteristic_id = j.characteristic_id
  FROM product_characteristics_join j
  WHERE old_characteristic_id = j.id;


/* --------- Fill score and votes for a products_characteristic_join --------- */

-- total score for each characteristic of each product --
UPDATE product_characteristics_join j
  SET total_score = sub_q.score_val
  FROM
    (
      SELECT SUM(cr.value) AS score_val, cr.characteristic_id, r.product_id
      FROM characteristics_reviews cr JOIN reviews r
      ON cr.review_id = r.review_id
      GROUP BY r.product_id, cr.characteristic_id
    ) AS sub_q
  WHERE j.product_id = sub_q.product_id and j.characteristic_id = sub_q.characteristic_id;

-- total count of votes for each characteristic for each product --
UPDATE product_characteristics_join j
  SET total_votes = sub_q.review_count
  FROM (
    SELECT COUNT(r.review_id) AS review_count, r.product_id
    FROM reviews r
    GROUP BY r.product_id
  ) AS sub_q
  WHERE j.product_id = sub_q.product_id;


/* ------------------------------ META DATA TABLE BUILD ------------------------------ */

-- unique product ids --
INSERT INTO meta (product_id)
  SELECT product_id
  FROM reviews
  ON CONFLICT (product_id) DO NOTHING;

-- recommended counts --
UPDATE meta m
  SET recommended = sub_q.recommended_count
  FROM (
    SELECT COUNT(*) FILTER (WHERE recommend) as recommended_count, r.product_id
    FROM reviews r
    GROUP BY r.product_id
  ) AS sub_q
  WHERE m.product_id = sub_q.product_id;

UPDATE meta m
  SET not_recommended = sub_q.not_recommended_count
  FROM (
    SELECT COUNT(*) FILTER (WHERE NOT recommend) as not_recommended_count, r.product_id
    FROM reviews r
    GROUP BY r.product_id
  ) AS sub_q
  WHERE m.product_id = sub_q.product_id;

-- ratings counts --
UPDATE meta m
  SET
    rating_1 = sub_q.rating_count_1,
    rating_2 = sub_q.rating_count_2,
    rating_3 = sub_q.rating_count_3,
    rating_4 = sub_q.rating_count_4,
    rating_5 = sub_q.rating_count_5
  FROM (
    SELECT
      COUNT(*) FILTER (WHERE rating = 1) AS rating_count_1,
      COUNT(*) FILTER (WHERE rating = 2) AS rating_count_2,
      COUNT(*) FILTER (WHERE rating = 3) AS rating_count_3,
      COUNT(*) FILTER (WHERE rating = 4) AS rating_count_4,
      COUNT(*) FILTER (WHERE rating = 5) AS rating_count_5,
      r.product_id
    FROM reviews r
    GROUP BY r.product_id
  ) AS sub_q
  WHERE m.product_id = sub_q.product_id;


/* ---------------- update date in reviews table UNIX --> DATETIME ---------------- */
ALTER TABLE reviews DROP COLUMN IF EXISTS date;
ALTER TABLE reviews ADD COLUMN date TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
UPDATE reviews r
  SET date = sub_q.iso_date
  FROM (
    SELECT TO_TIMESTAMP(date_unix/1000) AS iso_date, review_id
    FROM reviews
    GROUP BY review_id
  ) as sub_q
  WHERE r.review_id = sub_q.review_id;

/* ------------------------------- Drop old columns ------------------------------- */
ALTER TABLE characteristics_reviews DROP COLUMN old_characteristic_id;
ALTER TABLE product_characteristics_join DROP COLUMN characteristic_name;
ALTER TABLE reviews DROP COLUMN date_unix;

/* ---------------------------- Add secondary indices ---------------------------- */
CREATE INDEX reviews_product_id ON reviews (product_id);
CREATE INDEX photos_review_id ON photos (review_id);
CREATE INDEX prod_char_join_product_id ON product_characteristics_join (product_id);