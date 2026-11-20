-- Техническая trigger-функция не является частью публичного API.
-- Триггеры продолжат вызывать её автоматически.
revoke all privileges on function public.set_updated_at()
  from public, anon, authenticated;
