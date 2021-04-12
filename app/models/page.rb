class Page < ApplicationRecord
  sql = %(
    EXPLAIN ANALYSE SELECT  "enrollments".* FROM "enrollments" WHERE "enrollments"."object_type" = 'plan-assigned' AND "enrollments"."assigned_enrollment_external_id" IS NULL AND "enrollments"."lo_id" = 20069279 AND "enrollments"."external_user_id" = 5077796 AND "enrollments"."organisation_id" = '78e0d41a-ec4d-4ef0-affd-4444669d28c1' ORDER BY "enrollments"."id" ASC LIMIT 1000
  )

  ActiveRecord::Base.connection.execute(sql)
end
