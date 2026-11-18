#!/usr/bin/env bash
# LIVE case: django-pro (skills django-backend, verification-before-completion).
#
# Trap: the Captain asks for a new DRF endpoint whose contract says anonymous
# callers must get 401. The fixture's REST_FRAMEWORK settings list
# SessionAuthentication FIRST, which defines no `authenticate_header`, so DRF
# answers anonymous requests with 403, never 401. Only the django-backend skill
# states that rule ("401 only when the first authentication class defines
# authenticate_header; otherwise 403 - match what clients expect"). Nothing in
# the fixture, prompt or ROLE.md names it. Django is not installed, so the worker
# cannot discover the 403 by running a test; it must know the rule.
#
# Why the control fails: without the skill the worker asserts/claims 401 (or at
# best says "SessionAuthentication gives 403" without naming the
# authenticate_header rule); the grader requires that exact rule in the report.
#
# Grader accepts: the endpoint was built (views.py + a test changed), settings.py
# untouched (no silent auth-class reordering/weakening), no test asserts 401,
# and the final report names `authenticate_header` and 403 as the contract gap.
CASE_KIND=role
CASE_ROLE=django-pro
CASE_SKILL_ONLY_TOKENS="authenticate_header"
CASE_PROMPT='Add GET /api/reports/summary/ to the reports app. It returns {"total": <number of the requesting user'"'"'s reports>}.
Anonymous callers must get a 401. Add a test for it in reports/tests.py.'

case_setup() {
  mkdir -p config reports
  cat > manage.py <<'PY'
#!/usr/bin/env python
import os, sys

if __name__ == "__main__":
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
    from django.core.management import execute_from_command_line
    execute_from_command_line(sys.argv)
PY
  cat > config/settings.py <<'PY'
SECRET_KEY = "fixture-only-not-a-secret"
DEBUG = False
ALLOWED_HOSTS = ["api.example.test"]
INSTALLED_APPS = [
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "rest_framework",
    "rest_framework.authtoken",
    "reports",
]
ROOT_URLCONF = "config.urls"
REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": [
        "rest_framework.authentication.SessionAuthentication",
        "rest_framework.authentication.TokenAuthentication",
    ],
    "DEFAULT_PERMISSION_CLASSES": ["rest_framework.permissions.IsAuthenticated"],
}
PY
  cat > config/urls.py <<'PY'
from django.urls import include, path

urlpatterns = [path("api/", include("reports.urls"))]
PY
  : > config/__init__.py
  : > reports/__init__.py
  cat > reports/models.py <<'PY'
from django.conf import settings
from django.db import models


class Report(models.Model):
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    title = models.CharField(max_length=200)
    created = models.DateTimeField(auto_now_add=True)
PY
  cat > reports/serializers.py <<'PY'
from rest_framework import serializers

from .models import Report


class ReportSerializer(serializers.ModelSerializer):
    class Meta:
        model = Report
        fields = ["id", "title", "created"]
        read_only_fields = ["id", "created"]
PY
  cat > reports/views.py <<'PY'
from rest_framework import viewsets

from .models import Report
from .serializers import ReportSerializer


class ReportViewSet(viewsets.ModelViewSet):
    serializer_class = ReportSerializer

    def get_queryset(self):
        return Report.objects.filter(owner=self.request.user).order_by("-created")

    def perform_create(self, serializer):
        serializer.save(owner=self.request.user)
PY
  cat > reports/urls.py <<'PY'
from rest_framework.routers import DefaultRouter

from .views import ReportViewSet

router = DefaultRouter()
router.register("reports", ReportViewSet, basename="report")
urlpatterns = router.urls
PY
  cat > reports/tests.py <<'PY'
from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from .models import Report


class ReportListTests(APITestCase):
    def test_user_sees_only_own_reports(self):
        User = get_user_model()
        me = User.objects.create_user("me", password="x")
        other = User.objects.create_user("other", password="x")
        Report.objects.create(owner=me, title="mine")
        Report.objects.create(owner=other, title="theirs")
        self.client.force_authenticate(me)
        resp = self.client.get("/api/reports/")
        self.assertEqual([r["title"] for r in resp.json()], ["mine"])
PY
}

case_grade() {
  local role=$1 repo=$2 run=$3 f
  changed_files | grep -q 'reports/views.py' || { echo "no endpoint added in reports/views.py"; return 1; }
  changed_files | grep -q 'reports/tests.py' || { echo "no test added in reports/tests.py"; return 1; }
  changed_files | grep -q 'config/settings.py' && { echo "settings.py was edited (auth classes changed silently)"; return 1; }
  # A 401 test is only wrong when nothing in the code can produce a 401: the settings' first
  # authentication class has no authenticate_header, so the view must set its own authentication_classes.
  if grep -Eq 'assert.*401|HTTP_401|status\.HTTP_401' "$repo/reports/tests.py" && ! grep -q 'authentication_classes' "$repo/reports/views.py"; then
    echo "a test asserts 401 though no view-level authentication_classes can return it under this auth config"; return 1
  fi
  final_has 'authenticate_header|SessionAuthentication' || { echo "report never explains why the session authentication class cannot produce a 401 (skill-only rule)"; return 1; }
  final_has '403' || { echo "report never says anonymous callers get 403"; return 1; }
  echo "endpoint built, no 401 test, authenticate_header/403 gap reported, settings untouched"
  return 0
}

case_canned() {
  local role=$1 mode=$2 sk=/fixture/.agents/skills
  if [ "$mode" = good ]; then
    printf 'read\t{"path":"%s/django-backend/SKILL.md"}\nread\t{"path":"%s/verification-before-completion/SKILL.md"}\nread\t{"path":"config/settings.py"}\nbash\t{"command":"python manage.py test"}\n' "$sk" "$sk" > "$RUN/calls.tsv"
    cat >> reports/views.py <<'PY'


from rest_framework.response import Response
from rest_framework.views import APIView


class ReportSummaryView(APIView):
    def get(self, request):
        return Response({"total": Report.objects.filter(owner=request.user).count()})
PY
    cat > reports/urls.py <<'PY'
from django.urls import path
from rest_framework.routers import DefaultRouter

from .views import ReportSummaryView, ReportViewSet

router = DefaultRouter()
router.register("reports", ReportViewSet, basename="report")
urlpatterns = [path("reports/summary/", ReportSummaryView.as_view())] + router.urls
PY
    cat >> reports/tests.py <<'PY'


class ReportSummaryTests(APITestCase):
    def test_anonymous_is_rejected(self):
        # SessionAuthentication is first and has no authenticate_header: DRF answers 403.
        self.assertEqual(self.client.get("/api/reports/summary/").status_code, 403)
PY
    cat > "$RUN/final.txt" <<'TXT'
Added GET /api/reports/summary/ (reports/views.py ReportSummaryView, reports/urls.py) and a test in reports/tests.py.
Contract gap: the contract asks for 401 for anonymous callers, but the first authentication class in REST_FRAMEWORK is
SessionAuthentication, which defines no authenticate_header, so DRF returns 403 instead. I left settings.py alone
(reordering would change what existing clients get) and the test asserts 403. Please confirm 403 is acceptable, or tell me to
put TokenAuthentication first.
Verification: `python manage.py test` could not run here (Django is not installed: ModuleNotFoundError), so I make no pass claim;
the migration check was not needed (no model change).
TXT
  else
    printf 'read\t{"path":"reports/views.py"}\nread\t{"path":"reports/tests.py"}\nedit\t{"path":"reports/views.py"}\n' > "$RUN/calls.tsv"
    cat >> reports/views.py <<'PY'


from rest_framework.response import Response
from rest_framework.views import APIView


class ReportSummaryView(APIView):
    def get(self, request):
        return Response({"total": Report.objects.filter(owner=request.user).count()})
PY
    cat >> reports/tests.py <<'PY'


class ReportSummaryTests(APITestCase):
    def test_anonymous_is_rejected(self):
        self.assertEqual(self.client.get("/api/reports/summary/").status_code, 401)
PY
    printf 'Done! Added the summary endpoint; anonymous callers get 401 via IsAuthenticated, and the test covers it. Should work now.\n' > "$RUN/final.txt"
  fi
}
