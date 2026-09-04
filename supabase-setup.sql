-- ============================================
-- Alcumus Clone - Supabase Database Setup
-- ============================================
-- HOW TO USE:
-- 1. Go to your Supabase Dashboard
-- 2. Click "SQL Editor" in the left sidebar
-- 3. Click "New Query"
-- 4. Paste this ENTIRE file
-- 5. Click "Run"
-- ============================================


-- ============================================
-- 1. CREATE TABLES
-- ============================================

-- Subjects (e.g., "Calculus II", "Pre-Calculus")
CREATE TABLE subjects (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    level TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- User profiles (extends the built-in auth.users table)
CREATE TABLE profiles (
    id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
    name TEXT DEFAULT 'New User',
    institute TEXT DEFAULT '',
    major TEXT DEFAULT '',
    picture_url TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Math problems
CREATE TABLE problems (
    id SERIAL PRIMARY KEY,
    subject_id INTEGER REFERENCES subjects(id) ON DELETE CASCADE,
    topic TEXT NOT NULL,
    problem_text TEXT NOT NULL,
    answer TEXT NOT NULL,
    solution TEXT NOT NULL,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- User progress (every single attempt is recorded)
CREATE TABLE user_progress (
    id SERIAL PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    problem_id INTEGER REFERENCES problems(id) ON DELETE CASCADE NOT NULL,
    is_correct BOOLEAN NOT NULL,
    user_answer TEXT DEFAULT '',
    attempted_at TIMESTAMPTZ DEFAULT NOW()
);


-- ============================================
-- 2. ENABLE ROW LEVEL SECURITY (RLS)
-- ============================================
-- RLS makes sure users can only access data they're allowed to.

ALTER TABLE subjects ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE problems ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_progress ENABLE ROW LEVEL SECURITY;


-- ============================================
-- 3. CREATE SECURITY POLICIES
-- ============================================

-- Subjects: anyone can read
CREATE POLICY "Subjects are viewable by everyone"
    ON subjects FOR SELECT USING (true);

-- Profiles: anyone can read all profiles, but only edit your own
CREATE POLICY "Profiles are viewable by everyone"
    ON profiles FOR SELECT USING (true);
CREATE POLICY "Users can insert own profile"
    ON profiles FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "Users can update own profile"
    ON profiles FOR UPDATE USING (auth.uid() = id);

-- Problems: anyone can read, logged-in users can add new ones
CREATE POLICY "Problems are viewable by everyone"
    ON problems FOR SELECT USING (true);
CREATE POLICY "Authenticated users can add problems"
    ON problems FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- User progress: you can only see and write YOUR OWN progress
CREATE POLICY "Users can view own progress"
    ON user_progress FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own progress"
    ON user_progress FOR INSERT WITH CHECK (auth.uid() = user_id);


-- ============================================
-- 4. AUTO-CREATE PROFILE ON SIGNUP
-- ============================================
-- When someone signs up, this automatically creates their profile row.

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, name)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'name', 'New User')
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- ============================================
-- 5. SEED DATA
-- ============================================

-- Add subjects
INSERT INTO subjects (name, level) VALUES
    ('Calculus II', 'Undergraduate'),
    ('Pre-Calculus', 'High School'),
    ('Algebra II', 'High School'),
    ('Geometry', 'High School'),
    ('Gen Phy II', 'Undergraduate');

-- Add the 2 initial Calculus II problems (subject_id = 1)
INSERT INTO problems (subject_id, topic, problem_text, answer, solution) VALUES
(1, 'Integration by Parts',
 'Evaluate the integral: \( \int x e^x \, dx \)',
 'xe^x - e^x',
 'Using integration by parts: let \( u = x \) and \( dv = e^x dx \). Then \( du = dx \) and \( v = e^x \). The formula is \( uv - \int v \, du = x e^x - \int e^x \, dx = x e^x - e^x + C \).'),

(1, 'Trigonometric Integrals',
 'Evaluate the integral: \( \int \sin^2(x) \, dx \) (ignore the constant C)',
 'x/2 - sin(2x)/4',
 'Use the half-angle identity: \( \sin^2(x) = \frac{1 - \cos(2x)}{2} \). Integrating this yields \( \frac{x}{2} - \frac{\sin(2x)}{4} \).');
