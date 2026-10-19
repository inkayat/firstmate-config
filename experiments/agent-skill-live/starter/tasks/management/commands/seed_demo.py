from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand
from django.db import transaction
from tasks.models import Task


class Command(BaseCommand):
    help = "Create synthetic sample users and tasks on a local sandbox database."

    @transaction.atomic
    def handle(self, *args, **options):
        for name in ("alice", "bob"):
            user, created = get_user_model().objects.get_or_create(username=f"sample-{name}")
            if created:
                user.set_password(f"synthetic-{name}")
                user.save(update_fields=["password"])
            for title, completed in [(f"{name.title()} draft", False), (f"{name.title()} finished", True)]:
                Task.objects.get_or_create(owner=user, title=title, defaults={"completed": completed})
        self.stdout.write("Synthetic users sample-alice and sample-bob ready (two tasks each on a fresh database).")
