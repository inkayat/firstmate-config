import base64
from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase
from .models import Task


class TaskAPITests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.alice = get_user_model().objects.create_user(username="sample-alice", password="synthetic-alice")
        cls.bob = get_user_model().objects.create_user(username="sample-bob", password="synthetic-bob")
        cls.own = Task.objects.create(owner=cls.alice, title="Alice draft")
        cls.other = Task.objects.create(owner=cls.bob, title="Bob draft")

    def setUp(self):
        token = base64.b64encode(b"sample-alice:synthetic-alice").decode()
        self.client.credentials(HTTP_AUTHORIZATION=f"Basic {token}")

    def test_authentication_required(self):
        self.client.credentials()
        for method, path, data in [
            ("get", "/api/tasks/", None),
            ("post", "/api/tasks/", {"title": "Hidden"}),
            ("get", f"/api/tasks/{self.own.pk}/", None),
            ("patch", f"/api/tasks/{self.own.pk}/", {"title": "Hidden"}),
        ]:
            with self.subTest(method=method):
                response = getattr(self.client, method)(path, data, format="json")
                self.assertEqual(response.status_code, 401)

    def test_list_and_detail_only_expose_owned_tasks(self):
        response = self.client.get("/api/tasks/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), [{"id": self.own.pk, "owner": self.alice.pk, "title": "Alice draft", "completed": False}])
        self.assertEqual(self.client.get(f"/api/tasks/{self.own.pk}/").json(), response.json()[0])
        self.assertEqual(self.client.get(f"/api/tasks/{self.other.pk}/").status_code, 404)

    def test_create_assigns_authenticated_owner(self):
        response = self.client.post("/api/tasks/", {"title": "New task", "owner": self.bob.pk}, format="json")
        self.assertEqual(response.status_code, 201)
        created = Task.objects.get(pk=response.json()["id"])
        self.assertEqual((created.owner_id, created.title, created.completed), (self.alice.pk, "New task", False))

    def test_patch_cannot_reassign_owner(self):
        response = self.client.patch(f"/api/tasks/{self.own.pk}/", {"completed": True, "owner": self.bob.pk}, format="json")
        self.assertEqual(response.status_code, 200)
        self.own.refresh_from_db()
        self.assertEqual((self.own.owner_id, self.own.completed, self.own.title), (self.alice.pk, True, "Alice draft"))

    def test_put_updates_owned_task(self):
        response = self.client.put(f"/api/tasks/{self.own.pk}/", {"title": "Replaced", "completed": True}, format="json")
        self.assertEqual(response.status_code, 200)
        self.own.refresh_from_db()
        self.assertEqual((self.own.title, self.own.completed), ("Replaced", True))

    def test_foreign_updates_return_not_found_without_mutation(self):
        for method in ("patch", "put"):
            with self.subTest(method=method):
                response = getattr(self.client, method)(f"/api/tasks/{self.other.pk}/", {"title": "Intrusion", "completed": True}, format="json")
                self.assertEqual(response.status_code, 404)
        self.other.refresh_from_db()
        self.assertEqual((self.other.title, self.other.completed, self.other.owner_id), ("Bob draft", False, self.bob.pk))

    def test_invalid_title_is_rejected(self):
        for title in ("", "x" * 201):
            with self.subTest(title=title):
                response = self.client.post("/api/tasks/", {"title": title}, format="json")
                self.assertEqual(response.status_code, 400)
                self.assertIn("title", response.json())
        self.assertEqual(Task.objects.filter(owner=self.alice).count(), 1)
