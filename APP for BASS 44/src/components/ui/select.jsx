"use client"

import * as React from "react"
import * as SelectPrimitive from "@radix-ui/react-select"
import { Check, ChevronDown, ChevronUp } from "lucide-react"
import { cn } from "@/lib/utils"
import {
  Drawer,
  DrawerContent,
  DrawerHeader,
  DrawerTitle,
} from "@/components/ui/drawer"

// Detect touch/mobile
const isMobile = () => typeof window !== "undefined" && window.matchMedia("(pointer: coarse)").matches;

const Select = SelectPrimitive.Root
const SelectGroup = SelectPrimitive.Group
const SelectValue = SelectPrimitive.Value

const SelectTrigger = React.forwardRef(({ className, children, ...props }, ref) => (
  <SelectPrimitive.Trigger
    ref={ref}
    className={cn(
      "flex h-9 w-full items-center justify-between whitespace-nowrap rounded-md border border-input bg-transparent px-3 py-2 text-sm shadow-sm ring-offset-background data-[placeholder]:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-ring disabled:cursor-not-allowed disabled:opacity-50 [&>span]:line-clamp-1 active:scale-95 transition-transform",
      className
    )}
    {...props}>
    {children}
    <SelectPrimitive.Icon asChild>
      <ChevronDown className="h-4 w-4 opacity-50" />
    </SelectPrimitive.Icon>
  </SelectPrimitive.Trigger>
))
SelectTrigger.displayName = SelectPrimitive.Trigger.displayName

const SelectScrollUpButton = React.forwardRef(({ className, ...props }, ref) => (
  <SelectPrimitive.ScrollUpButton
    ref={ref}
    className={cn("flex cursor-default items-center justify-center py-1", className)}
    {...props}>
    <ChevronUp className="h-4 w-4" />
  </SelectPrimitive.ScrollUpButton>
))
SelectScrollUpButton.displayName = SelectPrimitive.ScrollUpButton.displayName

const SelectScrollDownButton = React.forwardRef(({ className, ...props }, ref) => (
  <SelectPrimitive.ScrollDownButton
    ref={ref}
    className={cn("flex cursor-default items-center justify-center py-1", className)}
    {...props}>
    <ChevronDown className="h-4 w-4" />
  </SelectPrimitive.ScrollDownButton>
))
SelectScrollDownButton.displayName = SelectPrimitive.ScrollDownButton.displayName

const SelectContent = React.forwardRef(({ className, children, position = "popper", ...props }, ref) => (
  <SelectPrimitive.Portal>
    <SelectPrimitive.Content
      ref={ref}
      className={cn(
        "relative z-50 max-h-96 min-w-[8rem] overflow-hidden rounded-md border bg-popover text-popover-foreground shadow-md data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0 data-[state=closed]:zoom-out-95 data-[state=open]:zoom-in-95 data-[side=bottom]:slide-in-from-top-2 data-[side=left]:slide-in-from-right-2 data-[side=right]:slide-in-from-left-2 data-[side=top]:slide-in-from-bottom-2",
        position === "popper" &&
          "data-[side=bottom]:translate-y-1 data-[side=left]:-translate-x-1 data-[side=right]:translate-x-1 data-[side=top]:-translate-y-1",
        className
      )}
      position={position}
      {...props}>
      <SelectScrollUpButton />
      <SelectPrimitive.Viewport
        className={cn("p-1", position === "popper" &&
          "h-[var(--radix-select-trigger-height)] w-full min-w-[var(--radix-select-trigger-width)]")}>
        {children}
      </SelectPrimitive.Viewport>
      <SelectScrollDownButton />
    </SelectPrimitive.Content>
  </SelectPrimitive.Portal>
))
SelectContent.displayName = SelectPrimitive.Content.displayName

const SelectLabel = React.forwardRef(({ className, ...props }, ref) => (
  <SelectPrimitive.Label
    ref={ref}
    className={cn("px-2 py-1.5 text-sm font-semibold", className)}
    {...props} />
))
SelectLabel.displayName = SelectPrimitive.Label.displayName

const SelectItem = React.forwardRef(({ className, children, ...props }, ref) => (
  <SelectPrimitive.Item
    ref={ref}
    className={cn(
      "relative flex w-full cursor-default select-none items-center rounded-sm py-1.5 pl-2 pr-8 text-sm outline-none focus:bg-accent focus:text-accent-foreground data-[disabled]:pointer-events-none data-[disabled]:opacity-50",
      className
    )}
    {...props}>
    <span className="absolute right-2 flex h-3.5 w-3.5 items-center justify-center">
      <SelectPrimitive.ItemIndicator>
        <Check className="h-4 w-4" />
      </SelectPrimitive.ItemIndicator>
    </span>
    <SelectPrimitive.ItemText>{children}</SelectPrimitive.ItemText>
  </SelectPrimitive.Item>
))
SelectItem.displayName = SelectPrimitive.Item.displayName

const SelectSeparator = React.forwardRef(({ className, ...props }, ref) => (
  <SelectPrimitive.Separator
    ref={ref}
    className={cn("-mx-1 my-1 h-px bg-muted", className)}
    {...props} />
))
SelectSeparator.displayName = SelectPrimitive.Separator.displayName

// Mobile-native Select using Drawer
function MobileSelect({ value, onValueChange, children, placeholder, label }) {
  const [open, setOpen] = React.useState(false);

  // Collect SelectItem children to render in drawer
  const items = [];
  React.Children.forEach(children, child => {
    if (!child) return;
    // Handle SelectContent wrapping
    if (child.props?.children) {
      React.Children.forEach(child.props.children, item => {
        if (item?.type === SelectItem || (item?.props && item?.props?.value !== undefined)) {
          items.push(item);
        }
      });
    }
  });

  // Find label of current value
  let displayLabel = placeholder;
  items.forEach(item => {
    if (item?.props?.value === value) {
      displayLabel = item.props.children;
    }
  });

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="flex h-9 w-full items-center justify-between whitespace-nowrap rounded-md border border-input bg-transparent px-3 py-2 text-sm shadow-sm text-foreground active:scale-95 transition-transform"
      >
        <span className={value ? "" : "text-muted-foreground"}>{displayLabel}</span>
        <ChevronDown className="h-4 w-4 opacity-50" />
      </button>
      <Drawer open={open} onOpenChange={setOpen}>
        <DrawerContent>
          {label && (
            <DrawerHeader>
              <DrawerTitle>{label}</DrawerTitle>
            </DrawerHeader>
          )}
          <div className="p-4 pb-8 space-y-1 overflow-y-auto max-h-[60vh]">
            {items.map((item, i) => {
              const itemValue = item?.props?.value;
              const isSelected = itemValue === value;
              return (
                <button
                  key={itemValue ?? i}
                  type="button"
                  onClick={() => { onValueChange?.(itemValue); setOpen(false); }}
                  className={cn(
                    "w-full flex items-center justify-between px-4 py-3 rounded-xl text-sm transition-colors active:scale-95",
                    isSelected ? "bg-primary text-primary-foreground font-medium" : "hover:bg-accent"
                  )}
                >
                  <span>{item?.props?.children}</span>
                  {isSelected && <Check className="h-4 w-4" />}
                </button>
              );
            })}
          </div>
        </DrawerContent>
      </Drawer>
    </>
  );
}

// Smart Select that switches between native Radix and Drawer on mobile
function SmartSelect({ value, defaultValue, onValueChange, children, placeholder, label, ...props }) {
  const [mobile, setMobile] = React.useState(false);
  React.useEffect(() => { setMobile(isMobile()); }, []);

  if (mobile) {
    return (
      <MobileSelect value={value} onValueChange={onValueChange} placeholder={placeholder} label={label}>
        {children}
      </MobileSelect>
    );
  }

  return (
    <Select value={value} defaultValue={defaultValue} onValueChange={onValueChange} {...props}>
      {children}
    </Select>
  );
}

export {
  SmartSelect,
  Select,
  SelectGroup,
  SelectValue,
  SelectTrigger,
  SelectContent,
  SelectLabel,
  SelectItem,
  SelectSeparator,
  SelectScrollUpButton,
  SelectScrollDownButton,
}