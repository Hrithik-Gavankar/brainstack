import App from "./App";
import { AdminReviewApp } from "./admin/AdminReviewApp";

const isAdminReviewRoute = (): boolean => {
  const base = import.meta.env.BASE_URL.replace(/\/$/, "");
  const path = window.location.pathname.replace(/\/$/, "");
  const suffix = base ? `${base}/admin/review` : "/admin/review";
  return path === suffix || path.endsWith("/admin/review");
};

export const Root = () => {
  if (isAdminReviewRoute()) {
    return <AdminReviewApp />;
  }
  return <App />;
};

export default Root;
