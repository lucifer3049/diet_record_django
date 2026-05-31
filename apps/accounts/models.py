from django.contrib.auth.models import AbstractUser


class User(AbstractUser):
    """先建立自訂 User 以鎖定 AUTH_USER_MODEL；M1 再擴充 profile 欄位。"""
