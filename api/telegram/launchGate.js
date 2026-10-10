// Legacy deployments must obey the same server launch and mobile admission rules.
export function legacyLaunchGate(req, res, now = Date.now()) {
  if (now < Date.parse('2026-10-12T18:00:00Z')) {
    res.status(423).json({ error: 'GAME_NOT_LAUNCHED', launchAt: '2026-10-12T18:00:00Z' });
    return true;
  }
  if (!['android', 'ios'].includes(req.body?.platform) || !/Android|iPhone|iPad|iPod/i.test(req.headers?.['user-agent'] ?? '')) {
    res.status(403).json({ error: 'MOBILE_TELEGRAM_REQUIRED' });
    return true;
  }
  return false;
}