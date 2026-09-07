-- ============================================
-- Alcumus Clone - LEARN Page Setup
-- ============================================
-- Run this AFTER supabase-setup.sql, the same way:
-- Supabase Dashboard > SQL Editor > New Query > paste > Run
--
-- Adds the topic map that powers the LEARN page, plus the
-- metadata columns that let problems be filtered by
-- subtopic / source / year / difficulty.
-- ============================================


-- ============================================
-- 1. CREATE TABLES
-- ============================================

-- Topics: the top level of the LEARN map (e.g. "Series")
CREATE TABLE topics (
    id SERIAL PRIMARY KEY,
    subject_id INTEGER REFERENCES subjects(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    name_th TEXT DEFAULT '',
    section_ref TEXT DEFAULT '',          -- textbook sections, e.g. "11.2-11.7"
    sort_order INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Subtopics: the second level (e.g. "11.4 The Comparison Tests")
CREATE TABLE subtopics (
    id SERIAL PRIMARY KEY,
    topic_id INTEGER REFERENCES topics(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    section_ref TEXT DEFAULT '',
    sort_order INTEGER DEFAULT 0
);

-- Resources: what opens in the popup for a topic (clips and sheets)
-- url is NULLABLE on purpose: a resource can be listed before the
-- file is uploaded, and the UI shows it greyed out until it has a url.
CREATE TABLE resources (
    id SERIAL PRIMARY KEY,
    topic_id INTEGER REFERENCES topics(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK (kind IN ('video', 'sheet')),
    title TEXT NOT NULL,
    url TEXT,
    start_seconds INTEGER,                -- deep-link into a YouTube clip
    sort_order INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);


-- ============================================
-- 2. EXTEND THE problems TABLE
-- ============================================
-- The existing free-text `topic` column stays so nothing breaks.
-- These add the axes the worksheet generator filters on.

ALTER TABLE problems ADD COLUMN IF NOT EXISTS topic_id    INTEGER REFERENCES topics(id) ON DELETE SET NULL;
ALTER TABLE problems ADD COLUMN IF NOT EXISTS subtopic_id INTEGER REFERENCES subtopics(id) ON DELETE SET NULL;
ALTER TABLE problems ADD COLUMN IF NOT EXISTS source      TEXT;      -- 'Midterm 2567', 'Exercise 04'
ALTER TABLE problems ADD COLUMN IF NOT EXISTS year        INTEGER;   -- Buddhist year, e.g. 2567
ALTER TABLE problems ADD COLUMN IF NOT EXISTS difficulty  SMALLINT CHECK (difficulty BETWEEN 1 AND 5);

CREATE INDEX IF NOT EXISTS problems_topic_id_idx    ON problems(topic_id);
CREATE INDEX IF NOT EXISTS problems_subtopic_id_idx ON problems(subtopic_id);


-- ============================================
-- 3. ROW LEVEL SECURITY
-- ============================================
-- Same shape as the existing tables: everyone reads, signed-in users write.

ALTER TABLE topics    ENABLE ROW LEVEL SECURITY;
ALTER TABLE subtopics ENABLE ROW LEVEL SECURITY;
ALTER TABLE resources ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Topics are viewable by everyone"
    ON topics FOR SELECT USING (true);
CREATE POLICY "Authenticated users can add topics"
    ON topics FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "Subtopics are viewable by everyone"
    ON subtopics FOR SELECT USING (true);
CREATE POLICY "Authenticated users can add subtopics"
    ON subtopics FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "Resources are viewable by everyone"
    ON resources FOR SELECT USING (true);
CREATE POLICY "Authenticated users can add resources"
    ON resources FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);


-- ============================================
-- 4. SEED: 2301108 Calculus II midterm map
-- ============================================
-- Topics and section numbers are taken from the six exercise sets
-- and the Section 3 midterm review sheet (Stewart numbering).

INSERT INTO topics (subject_id, name, name_th, section_ref, sort_order) VALUES
    (1, 'Techniques of Integration', 'เทคนิคการอินทิเกรต', '7.1-7.2',   1),
    (1, 'Differential Equations',    'สมการเชิงอนุพันธ์',  '9.3, 9.5',  2),
    (1, 'Sequences',                 'ลำดับ',              '11.1',      3),
    (1, 'Series',                    'อนุกรม',             '11.2-11.7', 4),
    (1, 'Power Series',              'อนุกรมกำลัง',        '11.8-11.9', 5),
    (1, 'Taylor & Maclaurin Series', 'อนุกรมเทย์เลอร์',    '11.10-11.11', 6);

INSERT INTO subtopics (topic_id, name, section_ref, sort_order) VALUES
    -- Techniques of Integration (covers the two problems already in the DB)
    ((SELECT id FROM topics WHERE name = 'Techniques of Integration'), 'Integration by Parts',      '7.1',  1),
    ((SELECT id FROM topics WHERE name = 'Techniques of Integration'), 'Trigonometric Integrals',   '7.2',  2),
    -- Differential Equations
    ((SELECT id FROM topics WHERE name = 'Differential Equations'), 'Separable Equations',          '9.3',  1),
    ((SELECT id FROM topics WHERE name = 'Differential Equations'), 'Linear Equations',             '9.5',  2),
    -- Sequences
    ((SELECT id FROM topics WHERE name = 'Sequences'), 'Sequences',                                 '11.1', 1),
    -- Series
    ((SELECT id FROM topics WHERE name = 'Series'), 'Series',                                       '11.2', 1),
    ((SELECT id FROM topics WHERE name = 'Series'), 'The Integral Test and Estimates of Sums',      '11.3', 2),
    ((SELECT id FROM topics WHERE name = 'Series'), 'The Comparison Tests',                         '11.4', 3),
    ((SELECT id FROM topics WHERE name = 'Series'), 'Alternating Series and Absolute Convergence',  '11.5', 4),
    ((SELECT id FROM topics WHERE name = 'Series'), 'The Ratio and Root Tests',                     '11.6', 5),
    ((SELECT id FROM topics WHERE name = 'Series'), 'Strategy for Testing Series',                  '11.7', 6),
    -- Power Series
    ((SELECT id FROM topics WHERE name = 'Power Series'), 'Power Series',                                  '11.8', 1),
    ((SELECT id FROM topics WHERE name = 'Power Series'), 'Representations of Functions as Power Series',  '11.9', 2),
    -- Taylor & Maclaurin
    ((SELECT id FROM topics WHERE name = 'Taylor & Maclaurin Series'), 'Taylor and Maclaurin Series',      '11.10', 1),
    ((SELECT id FROM topics WHERE name = 'Taylor & Maclaurin Series'), 'Applications of Taylor Polynomials','11.11', 2);


-- Backfill the two seed problems onto the new topic map
UPDATE problems SET
    topic_id    = (SELECT id FROM topics    WHERE name = 'Techniques of Integration'),
    subtopic_id = (SELECT id FROM subtopics WHERE name = 'Integration by Parts')
WHERE topic = 'Integration by Parts';

UPDATE problems SET
    topic_id    = (SELECT id FROM topics    WHERE name = 'Techniques of Integration'),
    subtopic_id = (SELECT id FROM subtopics WHERE name = 'Trigonometric Integrals')
WHERE topic = 'Trigonometric Integrals';


-- ============================================
-- 5. SEED: resources
-- ============================================
-- The พี่ติวน้อง midterm review covers the whole midterm scope, so each
-- part is attached to every topic it actually reaches.
-- Sheets are listed with url = NULL until the PDFs are uploaded to
-- Supabase Storage; the LEARN page shows those greyed out.

INSERT INTO resources (topic_id, kind, title, url, sort_order)
SELECT t.id, 'video', v.title, v.url, v.sort_order
FROM topics t
CROSS JOIN (VALUES
    ('พี่ติวน้อง — Cal II Midterm Part 1/3', 'https://www.youtube.com/watch?v=GU0-lpU4QIk&list=PLNZdTVPAQvBCU5y4PDsmZW7v0ebjbd7wt', 1),
    ('พี่ติวน้อง — Cal II Midterm Part 2/3', 'https://www.youtube.com/watch?v=KdBe8eAHpgY&list=PLNZdTVPAQvBCU5y4PDsmZW7v0ebjbd7wt&index=2', 2),
    ('พี่ติวน้อง — Cal II Midterm Part 3/3', 'https://www.youtube.com/watch?v=N-zJsfahFc4&list=PLNZdTVPAQvBCU5y4PDsmZW7v0ebjbd7wt&index=3', 3)
) AS v(title, url, sort_order)
WHERE t.subject_id = 1
  AND t.name IN ('Differential Equations', 'Sequences', 'Series', 'Power Series', 'Taylor & Maclaurin Series');

INSERT INTO resources (topic_id, kind, title, url, sort_order) VALUES
    ((SELECT id FROM topics WHERE name = 'Differential Equations'),    'sheet', 'แบบฝึกหัดชุดที่ 1 — สมการเชิงอนุพันธ์ (2566)', NULL, 1),
    ((SELECT id FROM topics WHERE name = 'Sequences'),                 'sheet', 'แบบฝึกหัดชุดที่ 2 — ลำดับ (2566)',            NULL, 1),
    ((SELECT id FROM topics WHERE name = 'Series'),                    'sheet', 'แบบฝึกหัดชุดที่ 3 (2566)',                    NULL, 1),
    ((SELECT id FROM topics WHERE name = 'Series'),                    'sheet', 'แบบฝึกหัดชุดที่ 4 (2566)',                    NULL, 2),
    ((SELECT id FROM topics WHERE name = 'Power Series'),              'sheet', 'แบบฝึกหัดชุดที่ 5 (2566)',                    NULL, 1),
    ((SELECT id FROM topics WHERE name = 'Taylor & Maclaurin Series'), 'sheet', 'แบบฝึกหัดชุดที่ 6 (2566)',                    NULL, 1);

-- Midterm-wide sheets: attached to every midterm topic
INSERT INTO resources (topic_id, kind, title, url, sort_order)
SELECT t.id, 'sheet', s.title, NULL, s.sort_order
FROM topics t
CROSS JOIN (VALUES
    ('ทบทวนเนื้อหากลางภาค — Sec 3 (2567)', 10),
    ('แนวข้อสอบมิดเทอม Cal2 (2567)',        11)
) AS s(title, sort_order)
WHERE t.subject_id = 1
  AND t.name IN ('Differential Equations', 'Sequences', 'Series', 'Power Series', 'Taylor & Maclaurin Series');
