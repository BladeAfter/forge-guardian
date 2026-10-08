DO $mig$
DECLARE src text; patched text;
BEGIN
  src := pg_get_functiondef('public.fuse_heroes(bigint,uuid,uuid[],boolean,text,text)'::regprocedure);
  patched := replace(src,
    'if main.is_nft_exclusive then raise exception ''NFT_HERO_UNIQUE''; end if;',
    'if main.is_nft_exclusive and not p_use_fragments then raise exception ''NFT_HERO_FRAGMENTS_ONLY''; end if;');
  IF patched = src THEN RAISE EXCEPTION 'fuse_heroes patch target not found'; END IF;
  EXECUTE patched;

  src := pg_get_functiondef('public.get_hero_fusion_dashboard(bigint)'::regprocedure);
  patched := replace(src,
    '''next'', case when f.is_nft_exclusive or f.fusion_level',
    '''next'', case when f.fusion_level');
  IF patched = src THEN RAISE EXCEPTION 'get_hero_fusion_dashboard patch target not found'; END IF;
  EXECUTE patched;
END $mig$;