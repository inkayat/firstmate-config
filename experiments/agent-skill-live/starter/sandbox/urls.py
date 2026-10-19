from django.urls import path
from tasks.views import TaskDetail, TaskList

urlpatterns = [
    path("api/tasks/", TaskList.as_view(), name="task-list"),
    path("api/tasks/<int:pk>/", TaskDetail.as_view(), name="task-detail"),
]
