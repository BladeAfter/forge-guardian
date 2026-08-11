DROP POLICY IF EXISTS "Hero images are publicly readable" ON storage.objects;

CREATE POLICY "Hero catalog art is readable"
ON storage.objects FOR SELECT
TO anon, authenticated
USING (
  bucket_id = 'hero-images'
  AND (storage.foldername(name))[1] = 'heroes'
);
