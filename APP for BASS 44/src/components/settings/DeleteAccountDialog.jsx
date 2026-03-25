const db = globalThis.__B44_DB__ || { auth:{ isAuthenticated: async()=>false, me: async()=>null }, entities:new Proxy({}, { get:()=>({ filter:async()=>[], get:async()=>null, create:async()=>({}), update:async()=>({}), delete:async()=>({}) }) }), integrations:{ Core:{ UploadFile:async()=>({ file_url:'' }) } } };

import { useState } from "react";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import { Trash2 } from "lucide-react";

export default function DeleteAccountDialog() {
  const [loading, setLoading] = useState(false);

  const handleDelete = async () => {
    setLoading(true);
    await db.auth.logout();
  };

  return (
    <AlertDialog>
      <AlertDialogTrigger asChild>
        <button
          aria-label="删除账号"
          className="w-full min-h-[48px] flex items-center justify-center gap-2 rounded-2xl border border-red-200 text-red-500 text-sm font-medium hover:bg-red-50 active:scale-95 transition-all"
        >
          <Trash2 className="w-4 h-4" aria-hidden="true" />
          删除账号
        </button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>确认删除账号？</AlertDialogTitle>
          <AlertDialogDescription>
            此操作将永久删除您的账号及所有数据，且<strong>无法撤销</strong>。请确认您已了解此操作的后果。
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel aria-label="取消删除">取消</AlertDialogCancel>
          <AlertDialogAction
            aria-label="确认删除账号"
            onClick={handleDelete}
            disabled={loading}
            className="bg-red-500 hover:bg-red-600 focus:ring-red-500"
          >
            {loading ? "处理中..." : "确认删除"}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}