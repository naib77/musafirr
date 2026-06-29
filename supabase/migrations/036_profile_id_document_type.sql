-- Records which identity document a user uploaded during signup
-- (e.g. 'nid', 'passport', 'driving_license', 'student_id', 'office_id').
--
-- The two image slots continue to use owner_documents (nid_front / nid_back),
-- whose CHECK constraint and verification trigger remain unchanged; this column
-- only captures *what kind* of document those two images actually are, so the
-- guest can choose to upload something other than a National ID.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS id_document_type TEXT;
